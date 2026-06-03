# Research: Multi-Business Architecture & Grab-and-Go Beverage POS Patterns

**Tanggal:** 2026-06-03
**Konteks:** Teras Inn (dine-in restoran) berencana ekspansi ke bisnis ke-2 berupa kios Thai tea grab-and-go. Aplikasi `kasir_app` perlu dievolusi agar mendukung 1 owner dengan 2+ jenis bisnis berbeda, sekaligus mendukung mode "quick service" untuk minuman.

Tujuan dokumen ini adalah memberi **actionable insights**: pola arsitektur multi-business yang battle-tested dan referensi UI/UX kasir grab-and-go yang bisa langsung diadopsi.

---

## AREA A — Multi-Business / Multi-Outlet Architecture Patterns

### 1. Account Switching UX

Tiga pola dominan yang dipakai POS papan atas dan apps non-POS sebagai inspirasi:

| Pola | Contoh | Cocok kapan |
|------|--------|-------------|
| **Tap menu → "Switch location"** (modal/bottom sheet) | Square POS — di POS mobile, user tap "More > Switch location" lalu pilih lokasi | Cashier flow, jarang ganti dalam 1 shift |
| **Sidebar workspace switcher** (selalu visible) | Slack mobile — swipe kanan menampilkan sidebar workspace; Notion mobile workspace switcher di pojok kiri atas | Owner yang sering ganti, butuh konteks aktif yang sangat jelas |
| **Dashboard rollup + filter dropdown** | Square Dashboard app, Toast multi-location dashboard, Clover cloud dashboard | Owner mode untuk reporting, bukan transaksi |

**Insight untuk kasir_app:**
- Untuk **kasir di outlet**, lock device ke 1 outlet (login per device + "mode" assignment seperti Square). Kasir nggak boleh bisa switch sembarangan — itu attack surface untuk salah catat omzet.
- Untuk **owner**, kasih switcher gaya Slack/Notion: di header app atau drawer kiri, tampilkan business aktif + foto/inisial outlet, tap untuk buka bottom sheet daftar semua business + tombol "+ Tambah bisnis baru".
- UX terbaik adalah yang **selalu menampilkan "kamu sedang di mana"**, agar owner nggak salah input data ke business yang salah. Google Account Switcher dianggap referensi standar karena (1) menunjukkan akun aktif jelas, (2) menunjukkan akun lain yang sudah authenticated, (3) menyediakan "Add account" yang jelas. ([Jon Moore / UX Power Tools](https://medium.com/ux-power-tools/ways-to-design-account-switchers-app-switchers-743e05372ede))

Referensi:
- Square multi-location switching: https://squareup.com/help/us/en/article/5580-manage-multiple-locations-with-square
- Square — "modes" per device (assign device ke business type): https://squareup.com/help/us/en/article/5586-manage-devices-by-location
- Slack workspace switching mobile: https://slack.com/help/articles/1500002200741-Switch-between-workspaces
- Notion workspaces on mobile: https://www.notion.com/help/workspaces-on-mobile
- Pola account switcher: https://medium.com/ux-power-tools/ways-to-design-account-switchers-app-switchers-743e05372ede

---

### 2. Data Isolation Strategies

Tiga pola dasar multi-tenant DB (langsung dari literatur SaaS) dan kapan dipakai:

| Pola | Mekanisme | Pro | Kontra | Cocok untuk Teras Inn |
|------|-----------|-----|--------|----------------------|
| **Shared DB, Shared Schema** | 1 DB, semua tabel punya kolom `business_id` / `outlet_id`, filter di application layer | Murah, cepat develop, gampang reporting cross-business | Risk leakage tinggi kalau lupa WHERE clause; query perlu selalu sertakan tenant_id | **YES** untuk fase awal (cuma 2 business owned by 1 person) |
| **Shared DB, Separate Schema** | 1 DB, schema per tenant (Postgres-style); native DB-level isolation | Isolasi lebih kuat, performance isolation lebih baik | Migration jadi N×, query cross-tenant lebih sulit | Skip — overkill untuk 2 business |
| **Separate Databases** | 1 DB file per business, routing layer di app | Isolasi sempurna, tenant A crash tidak pengaruh B | Reporting cross-business jadi mahal (harus aggregate manual) | Skip — bikin laporan gabungan owner susah |

**Rekomendasi konkret untuk kasir_app (Flutter + Drift/SQLite lokal):**
- Pakai pendekatan **Shared DB + Shared Schema dengan kolom `business_id`** di semua tabel transaksional (`products`, `sales`, `sale_lines`, `inventory`, `staff_roles`, dll).
- Buat tabel induk `businesses(id, name, type ENUM('dine_in', 'grab_and_go'), created_at)` — kolom `type` menentukan mode UI cashier.
- Bungkus semua DAO/repository dengan **scoped query** yang otomatis inject `WHERE business_id = :active`. Cara aman: pakai pola "tenant context" — session/JWT-style claim `active_business_id` yang divalidasi di setiap query. ([WorkOS](https://workos.com/blog/developers-guide-saas-multi-tenant-architecture))
- Untuk kolom `tenant_id` di SQLite: tambahkan index gabungan `(business_id, created_at)` untuk semua tabel transaksional supaya filter cepat.
- Jika nanti pindah ke backend (sync ke cloud), pertimbangkan multi-DB pakai Turso (SQLite multi-tenant), atau tetap single-DB dengan Row-Level Security di Postgres.

Referensi:
- 3 pola multi-tenant DB: https://medium.com/@manu.venugopalan_55726/multi-tenant-saas-a-deep-dive-into-database-design-approaches-3a01fe0c083b
- Trade-off + diagram: https://www.bytebase.com/blog/multi-tenant-database-architecture-patterns-explained/
- Tenant context via session claim: https://workos.com/blog/developers-guide-saas-multi-tenant-architecture
- Turso multi-tenant SQLite (jika ke depan butuh sync cloud): https://turso.tech/blog/creating-a-multitenant-saas-service-with-turso-remix-and-drizzle-6205cf47
- Drizzle multi-tenant POC (referensi konsep): https://gist.github.com/gyopiazza/70919f2c97a01d1b9897057d11fb9933

---

### 3. Role-Based Access Control (RBAC)

Pola yang dipakai mayoritas POS (Lightspeed, Loyverse, Acid POS, dll):

**Default roles** (battle-tested):
- **Cashier** — proses sale, void minor, lihat shift sendiri. Tidak boleh: edit produk, lihat laporan, akses settings.
- **Manager** — semua hak cashier + void/refund, edit produk outlet sendiri, lihat laporan outlet sendiri, edit customer.
- **Owner/Admin** — full access semua business + onboard business baru + assign role.

**Pola assignment:**
- User punya tabel `user_business_roles(user_id, business_id, role)` — many-to-many. 1 user bisa punya role berbeda di tiap business.
- Owner Teras Inn = role `owner` di kedua business. Staff Thai tea kios = role `cashier` di Thai tea saja.
- Lightspeed menyebut secara eksplisit: *"Users can be assigned to specific outlets, or if desired, can be given access to all outlets"* — ini pola yang sesuai. ([Lightspeed X-Series](https://x-series-support.lightspeedhq.com/hc/en-us/articles/25534171377819-Setting-user-roles-and-permissions))

**Permission yang harus strictly controlled** (3 most-abused functions menurut Eposly):
1. **Voids** — butuh manager approval atau PIN
2. **Refunds** — log siapa yang approve
3. **Discounts** — batas maksimum per role, audit trail

**Best practice multi-outlet** (per Eposly):
- Centralisasi role definition (1 set role berlaku di semua business), assign per user-business pair.
- Audit log terpusat — owner harus bisa lihat semua action lintas business.

Referensi:
- Lightspeed roles & permissions: https://x-series-support.lightspeedhq.com/hc/en-us/articles/25534171377819-Setting-user-roles-and-permissions
- Multi-store RBAC best practice: https://eposly.io/blogs-insights/securing-multi-store-retail-with-role-based-pos-permissions/
- Acid POS roles: https://www.acidpos.com/features/user-permissions/

---

### 4. Cross-Business Reporting

Dua filosofi yang berbeda:

**A. Toast / Square style — "Group + Location filter"**
- Default view = aggregate semua location.
- Dropdown filter di header untuk drill-down ke 1 location.
- Comparison view side-by-side (Square Dashboard menonjolkan ini).
- Toast: *"compile data from all your locations into one dashboard"*. ([Toast](https://pos.toasttab.com/blog/on-the-line/how-to-manage-multiple-restaurant-locations))

**B. Lightspeed style — "Unified platform per-vertical"**
- Karena verticalnya beda (retail vs restaurant vs golf), setiap vertical punya report set sendiri tapi keuangan terkonsolidasi di backend Lightspeed central. ([Lightspeed Golf](https://www.lightspeedhq.com/golf/pos/golf-restaurant/))

**Insight untuk kasir_app** (di mana Teras Inn dan Thai tea memang **beda jenis bisnis**):
- Tabel reporting **per-business** harus tetap utama (karena modifier, COGS, kategori berbeda total).
- Untuk owner, sediakan **"Ringkasan Owner"** terpisah: cuma metric high-level (total omzet hari ini, total transaksi, profit kasar) yang bisa di-aggregate dengan unit yang sama (Rupiah). Hindari aggregate menu/produk karena beda total.
- Best practice consolidated dashboard untuk multi-entity: pull data ke 1 reporting DB dengan automatic sync, mapping ownership/data lineage eksplisit. ([Yonkers Times](https://yonkerstimes.com/fixing-the-data-blind-spot-why-multi-location-reporting-fails-without-one-dashboard/))
- Untuk laporan keuangan, posisikan tiap business sebagai "entity" terpisah (mirip multi-entity accounting) — supaya owner bisa lihat profit per business dan tidak salah ambil keputusan.

Referensi:
- Toast multi-location dashboard: https://pos.toasttab.com/products/multi-location-management
- Toast platform overview (groups & locations): https://doc.toasttab.com/doc/platformguide/platformToastPlatformOverview.html
- Square multi-location reporting via Dashboard app: https://squareup.com/us/en/the-bottom-line/inside-square/updated-square-pos-and-square-dashboard-app
- Multi-entity reporting principles: https://www.dualentry.com/scale/multi-entity-accounting-software
- Why multi-location reporting fails: https://yonkerstimes.com/fixing-the-data-blind-spot-why-multi-location-reporting-fails-without-one-dashboard/

---

### 5. Onboarding Business Kedua

Pola yang umum dipakai:

1. **Clone settings dari business existing** — Pawoon mengiklankan ini: bisa setup harga produk per outlet "tanpa perlu visit each outlet"; setting bisa di-clone dari outlet eksisting. ([Pawoon Help Center](https://www.pawoon-helpcenter.com/mengenal-paket-harga-pawoon-pos))
2. **Wizard step-by-step**: nama bisnis → tipe bisnis (dine-in / grab-and-go) → jam operasional → metode pembayaran → impor menu (atau pilih template) → assign staff.
3. **Template menu per vertical** — sediakan template "Coffee shop", "Bubble tea", "Restoran" yang bisa di-customize. Cara ini paling mempercepat onboarding owner pemula.
4. **POS Channel Duplicate** pattern (Agiliron) — duplikasi channel beri nama "X - Copy" dan clone seluruh settings, owner tinggal rename. ([Agiliron](https://learn.agiliron.com/docs/pos-channel-duplicate))

**Rekomendasi untuk kasir_app:**
- Setelah owner setup business pertama (Teras Inn dine-in), saat dia tap "+ Tambah Bisnis":
  - Step 1: nama + tipe (`dine_in` / `grab_and_go` / `retail`) — tipe ini menentukan mode UI cashier
  - Step 2: pilih "Mulai dari kosong" atau "Clone dari Teras Inn" (untuk re-use produk, tax, payment methods)
  - Step 3: jam operasional + alamat
  - Step 4: assign user existing atau invite baru
- Karena Thai tea **beda tipe** dengan dine-in, clone dari Teras Inn hanya untuk tax/payment/staff — produk harus dari template "Beverage" atau kosong.

Referensi:
- Pawoon multi-outlet pricing config: https://www.pawoon.com/v2/
- iReap multi-store dengan "transfer goods between stores": https://www.ireappos.com/news/en/ireap-pos-smart-cashier-app-for-modern-msmes/
- Olsera unlimited multi-outlet: https://www.olsera.com/en/pos
- Lightspeed multi-store setup duplication: https://www.lightspeedhq.com/pos/retail/midsize-business-pos/
- CAKE POS onboarding wizard: https://university.cake.net/support/s/article/POS-Onboarding-Wizard

---

### Real-World Reference Deep-Dive

#### Square (US)
- POS device punya konsep **"modes"**: device di-assign ke business type + location. Cashier yang login ke device tertentu otomatis kerja di context yang sudah diset. Bagus untuk security — kasir tidak bisa "salah pilih outlet". ([Square Modes](https://squareup.com/help/us/en/article/8458-use-modes-with-square-point-of-sale))
- Mode tersedia: Full service, Quick service, Bar — sangat relevan untuk Teras Inn (Full service) vs Thai tea (Quick service).
- Square Dashboard adalah app **terpisah** dari POS app — owner pakai Dashboard, kasir pakai POS. Pemisahan responsibility ini bagus.

#### Toast (US restaurant)
- Konsep **"restaurant group"** sebagai parent entity; setiap location adalah child. Settings bisa shared di group-level atau di-override per location.
- Menu management: 1 master menu, customize per location. Cocok kalau Teras Inn punya cabang ke-2 yang juga restoran.
- Tidak cocok untuk Thai tea karena Toast restaurant-focused.

#### Lightspeed (multi-vertical: retail + restaurant + golf)
- Contoh paling literal dari **"1 owner, multiple business types"** — owner golf course punya pro shop (retail), restaurant, dan tee sheet (booking) dalam 1 platform.
- Kunci: setiap vertical punya UI POS yang berbeda, tapi backend keuangan dan inventory terkoneksi.
- Pelajaran: jangan paksa 1 UI generik untuk semua tipe bisnis. Buat **mode UI yang berbeda per business type**, tapi share backend (auth, payment, customer, accounting).

#### Loyverse (international, populer di emerging markets)
- Multi-store dengan single account, **gratis untuk fitur dasar** — itu sebabnya populer.
- Store-specific inventory: item visibility per store (only items available in selected store shown).
- Pattern UI untuk switch: di Back Office (web), dropdown store di header. Di POS mobile, store di-set saat login.

#### Pawoon (Indonesia)
- Target: F&B + retail + barbershop + salon (sangat multi-vertical, sesuai Teras Inn use-case).
- Highlight: **multi-outlet price setting** dari 1 dashboard — owner tidak perlu fisik visit outlet untuk update harga.
- Cloud-based, real-time monitoring 18+ financial reports.

#### iReap (Indonesia, UMKM fokus)
- 2 tier: LITE (free, single store) dan PRO (multi-store via web admin `pro.ireappos.com`).
- Fitur khas: **transfer barang antar-toko** dengan tracking. Relevan kalau Teras Inn nanti supply bahan baku ke kios Thai tea.
- Offline mode dengan sync — penting untuk Indonesia (koneksi tidak stabil).

#### Olsera (Indonesia)
- Klaim unlimited multi-outlet di tier berbayar.
- Centralized CRM cross-outlet — customer bisa pakai membership di outlet manapun. Layak dipertimbangkan untuk Teras Inn jika nanti mau loyalty program lintas business.

#### Moka POS (Indonesia, sekarang Gojek)
- Sangat populer untuk UMKM F&B di Indonesia (kafe, restoran, kios).
- Penelitian akademik bahkan ada untuk implementasi Moka di Janji Jiwa. ([Untag Semarang](https://jurnal2.untagsmg.ac.id/index.php/soshumdik/article/view/126))
- Pola: tier pricing — fitur multi-outlet (laporan lanjutan, manajemen stok multi-outlet) berbayar tambahan.

---

## AREA B — Grab-and-Go Beverage POS Patterns

### 1. UI Cashier untuk Speed (1-2 detik per order)

Best practice dari Square QSR, Toast, dan POS bubble-tea-specific (Eats365, Snackpass, Chowbus, MenuSifu):

**Layout principles:**
- **Grid view dengan tile besar + foto** — Lightspeed: grid view shows items bigger (without prices); list view smaller (with prices). Untuk QSR, grid menang. ([Lightspeed](https://o-series-support.lightspeedhq.com/hc/en-us/articles/31329442916891-Design-your-POS-look-and-layout))
- **Eliminate scrolling di tablet** — semua menu harus fit dalam 1 screen (max 2 swipe). ([Dev.Pro](https://dev.pro/insights/designing-a-pos-system-ten-user-experience-tactics-that-improve-usability/))
- **One-tap combo / quick-add buttons** untuk item paling laris — Square menyebut "one-tap combo buttons" dan modifier yang "input the way customers speak". ([Square QSR](https://squareup.com/us/en/restaurants/quick-service))
- **Color-coded categories** — Hot/Iced jadi pemisah kategori utama, lalu sub-category (Thai tea, Milk tea, Fruit tea, dll).
- **Default product / favorites tray** — pin 6-8 best-seller di atas, akses 1 tap.

**Speed targets** (industri):
- Order placement to KDS hit: harus **instan** (lag = lost throughput di peak). ([Toast](https://pos.toasttab.com/blog/best-quick-service-pos-systems))
- Predefined order presets — Loyverse: *"Take orders in just one click with predefined sets of volumes"*. ([Loyverse](https://loyverse.com/bar-pos))
- Open ticket (parkir order) untuk kasus customer balik bayar setelah ambil — pattern Loyverse "Open Tickets". ([Loyverse Help](https://help.loyverse.com/help/open-tickets))

**Insight konkret untuk Thai tea kios:**
- Layout: header = mode switch (Hot / Iced) → grid 4×3 produk dengan foto + harga di pojok → sidebar kanan = current order + total + tombol Bayar.
- Pin top-5 best seller (Thai tea original, milk tea, green tea, dll) di row atas.
- Default modifier: ice level "normal", sugar "100%" — kasir cuma tap kalau customer minta ubah. Ini critical untuk speed.

Referensi:
- Square QSR: https://squareup.com/us/en/restaurants/quick-service
- POS UX 10 tactics: https://dev.pro/insights/designing-a-pos-system-ten-user-experience-tactics-that-improve-usability/
- Lightspeed POS layout: https://o-series-support.lightspeedhq.com/hc/en-us/articles/31329442916891-Design-your-POS-look-and-layout
- Toast best QSR features: https://pos.toasttab.com/blog/best-quick-service-pos-systems
- Loyverse predefined volumes: https://loyverse.com/bar-pos

---

### 2. Modifier System untuk Minuman (nested modifier)

Ini area paling penting untuk Thai tea. Best practice dari POS bubble-tea-specific:

**Struktur modifier yang lazim:**
1. **Size** (S/M/L) — radio, biasanya price-adjustment
2. **Temperature** (Hot/Iced) — radio, sering jadi top-level kategori (bukan modifier)
3. **Ice level** (Less Ice / Normal / Extra / No Ice) — radio, free
4. **Sugar level** (0% / 25% / 50% / 75% / 100%) — radio, free
5. **Toppings** (Boba, Jelly, Pudding, Cheese foam, Aloe, dll) — multi-select, **per-topping pricing**
6. **Milk type** (Fresh milk, Almond, Oat, dll) — radio, may have upcharge

Pola support dari Ginger POS: *"select drink → choose size (with price adjustment) → choose ice level → choose sugar level → add toppings (multiple selection with per-topping pricing) → choose milk type"* — ini **nested modifier groups unlimited**. ([Ginger](https://www.gingerserve.com/guides/best-pos-for-boba-tea-shops))

**UX yang lambat (anti-pattern):**
- Eats365 highlight masalah generic POS: *"navigate through multiple screens—often three or more—to adjust a single topping or customize sugar and ice levels"*. Ini bikin kasir lambat dan error tinggi. ([Eats365](https://www.eats365pos.com/blog/post/hidden-risks-generic-pos-bubble-tea))

**UX yang cepat (best practice):**
- **One-tap matrix / single screen modifier sheet** — semua modifier (size, ice, sugar, toppings) muncul dalam 1 modal/bottom-sheet, jadi kasir cuma 1 layar untuk customize 1 minuman.
- **Visual iconography** untuk ice level — ilustrasi ice cube yang bertambah seiring level (Sharetea style). Bantu customer/kasir paham lebih cepat. ([Sharetea](https://www.1992sharetea.com/news/how-to-customize-your-bubble-tea-order-at-sharetea))
- **Default value pre-selected** — ice "Normal", sugar "100%", topping "None". Mayoritas customer order standar, defaults menghemat tap.
- **Per-topping inventory link** — setiap topping di-link ke inventory item supaya auto-deduct stock (Boba habis → topping option grayed out). ([MenuSifu](https://www.menusifu.com/blog/pos-system-for-bubble-tea-shop))

**Insight konkret untuk Thai tea kios:**
- Tap produk → buka **bottom sheet modifier** dengan layout:
  - Row 1: Size [S][M][L] (M default)
  - Row 2: Ice [Less][Normal][Extra] (Normal default)
  - Row 3: Sugar [0][25][50][75][100] (100 default, atau 50 kalau target health-conscious)
  - Row 4: Toppings (grid 2×3) [Boba][Jelly][Pudding][Cheese Foam][None]
  - Bottom: total + tombol "Tambah ke Order"
- Total tap untuk minuman standar: 1 tap produk + 1 tap "Tambah". Custom order: 1 + 2-4 tap modifier + 1 tap tambah. Achievable dalam 3-5 detik.

Referensi:
- Ginger nested modifier flow: https://www.gingerserve.com/guides/best-pos-for-boba-tea-shops
- Eats365 — bahaya generic POS untuk bubble tea: https://www.eats365pos.com/blog/post/hidden-risks-generic-pos-bubble-tea
- MenuSifu — topping linked to inventory: https://www.menusifu.com/blog/pos-system-for-bubble-tea-shop
- Sharetea — visual ice level iconography: https://www.1992sharetea.com/news/how-to-customize-your-bubble-tea-order-at-sharetea
- Eats365 bubble tea must-haves: https://www.eats365pos.com/my/blog/post/bubble-tea-pos-must-haves
- Chowbus boba POS: https://www.chowbus.com/restaurant-pos/pos-system-for-bubble-tea-shop

---

### 3. Antrian / Queue Management

Pola umum di grab-and-go beverage:

**Mekanisme antrian:**
- **Nomor antrian per order**, di-print di struk + di-call saat ready.
- Auto-increment harian (reset jam 00:00) atau per-shift.
- Format simpel: 3 digit (001, 002, ...).
- Banyak POS Indonesia pakai **dedicated queue thermal printer** terpisah dari struk pembayaran. ([Queue Bee Solution](https://www.queuebeesolution.com/queue-management-system.php))

**Customer-facing display:**
- TV/monitor di pickup counter tampilkan: "Now serving: 042" + "Ready: 040, 041, 042" + "In progress: 043, 044".
- OrderReady app pattern: tap "ready" di POS → display update + announce nomor (sound + visual). ([OrderReady](https://www.orderready.app/))
- Alternatif Indonesia-friendly: SMS / WhatsApp notification ke nomor customer (lebih murah daripada TV display).

**Insight konkret untuk Thai tea kios:**
- Database: tambahkan `queue_number` di tabel `sales`, auto-increment per `business_id` per hari.
- Print queue number di bagian atas struk (besar, bold, font size 2-3×) — kasir bisa robek dan kasih ke customer, customer lihat nomornya.
- Phase 1 (MVP): cukup struk dengan nomor antrian + announce manual oleh barista.
- Phase 2 (saat scale): tablet/TV di counter untuk display "Now Serving" — bisa pakai Flutter web mode/standalone screen yang subscribe ke perubahan status order.
- Phase 3: notif WhatsApp / SMS — pakai gateway lokal.

Referensi:
- Queue management dengan ticket printer: https://www.queuebeesolution.com/queue-management-system.php
- Bluetooth queue number printer app (Android, Indonesia-friendly): https://play.google.com/store/apps/details?id=com.hardiyosodev.queue_number_bluetooth_printer
- OrderReady app pattern: https://www.orderready.app/
- SimpleTexting — SMS templates "order ready": https://simpletexting.com/blog/send-a-text-message-when-customers-food-is-ready/
- INFI self-order kiosk for boba (counter display reference): https://infi.us/boba-beverage/

---

### 4. Kitchen Ticket / Barista Display System

**Pola yang dipakai:**

**Format ticket (printed kitchen ticket — fallback paling murah):**
- Nomor antrian (besar)
- Daftar item: `1x Thai Tea M | Ice: Normal | Sugar: 75% | +Boba`
- Timestamp order
- Catatan khusus
- Pemisah jelas antar order

**Kitchen Display System (KDS) — replace kertas:**
- Layar digital di stasiun barista, real-time push dari POS.
- Joe Coffee KDS design highlight: *"itemized list of the order, including any and all modifications"* + *"visual indicators"* + *"modifiers or special requests all designed to reduce a barista's cognitive load"*. ([Joe Coffee](https://joe.coffee/blog/posts/coffee-shop-kds-system/))
- Order routing: bar station hanya tampilkan drink orders; food station hanya food. ([Square KDS](https://squareup.com/us/en/point-of-sale/restaurants/kitchen-display-system))
- Barista tap "Complete" saat selesai → POS update status → customer display update ke "Ready".

**Insight konkret untuk Thai tea kios:**
- Phase 1 (MVP, budget kecil): pakai **kitchen ticket printer thermal 58mm** terpisah dari cashier printer. Cetak otomatis tiap order masuk. Barista lihat di rak/clip-board.
- Phase 2: tablet (cheap Android) sebagai KDS dengan Flutter app. Subscribe ke event `order_created` lewat local socket / SQLite watch. Tampilkan card per-order dengan tombol "Selesai".
- Format ticket WAJIB tampilkan nomor antrian besar di atas — barista paling sering ngeliat ini untuk match dengan customer.
- Modifier harus **bullet-list, bukan inline** — barista capai cognitive overload kalau modifier dijadikan satu baris.

Contoh format ticket yang baik (58mm):
```
====================
   #042
====================
1x Thai Tea (M)
   - Ice: Less
   - Sugar: 50%
   - Topping: Boba, Jelly
--------------------
1x Green Tea (L)
   - Ice: Normal
   - Sugar: 100%
   - Topping: -
====================
18:42  Kasir: Lia
```

Referensi:
- Coffee shop KDS principles: https://joe.coffee/blog/posts/coffee-shop-kds-system/
- KDS station routing: https://squareup.com/us/en/point-of-sale/restaurants/kitchen-display-system
- Lightspeed KDS: https://www.lightspeedhq.com/pos/restaurant/kitchen-display-system/
- Loyverse KDS: https://help.loyverse.com/help/kitchen-display-system

---

### 5. Receipt Format untuk Grab-and-Go

**Format thermal 58mm (paling umum untuk kios kecil di Indonesia):**

Karakteristik 58mm:
- Lebih kecil, hemat ruang counter, hemat kertas, harga printer < $50. ([HPRT](https://www.hprt.com/blog/Why-Choose-a-58mm-Receipt-Printer-for-Your-Small-Retail-Businesses-and-Takeaway-Shops.html))
- Lebar print effective ~32 karakter monospace.
- Cocok untuk takeaway / grab-and-go karena info yang dicetak minim.

**Konten yang harus ada (minimum viable receipt):**
```
====================
  TERAS THAI TEA
  Jl. Diponegoro 52
====================

  ANTRIAN: #042

--------------------
1x Thai Tea (M)
   Ice:Less Sugar:50%
   +Boba +Jelly
   Rp 25.000

1x Green Tea (L)
   Ice:Normal Sugar:100%
   Rp 22.000
--------------------
Subtotal  Rp 47.000
PPN 11%   Rp  5.170
--------------------
TOTAL     Rp 52.170

Bayar (QRIS) Rp 52.170
--------------------
03/06/2026 18:42
Kasir: Lia

  TERIMA KASIH!
  Order via WA:
  0812-3456-7890
====================
```

**Best practice tambahan:**
- **Nomor antrian SUPER BESAR** di atas (2-3× ukuran font normal) — supaya gampang dibaca dari kejauhan saat barista call.
- Modifier dijadikan baris terpisah dengan indent, jangan inline panjang.
- Tax / PPN ditampilkan terpisah karena regulasi.
- QRIS / payment method jelas.
- Footer: kontak WA untuk order ulang (drive repeat customer).

Referensi:
- 58mm thermal printer untuk kios kecil: https://www.hprt.com/blog/Why-Choose-a-58mm-Receipt-Printer-for-Your-Small-Retail-Businesses-and-Takeaway-Shops.html
- iReap — guide thermal printers untuk Indonesia: https://www.ireappos.com/news/en/thermal-printers-types-and-recommendations/
- Nutapos — printer untuk usaha minuman: https://nutapos.com/post/fungsi-printer-kasir-untuk-usaha-minuman/

---

### Real-World Reference Deep-Dive (Beverage)

#### Square for Restaurants — Quick Service Mode
- Mode tersedia: Full service, Quick service, Bar — bisa switch per device.
- *"customizable displays, menu photos, and an intuitive interface designed for fast service"*.
- Staff training < 15 menit (klaim Square).
- Modifier "input the way customers speak" — natural language flow.
- Cocok jadi referensi utama UI Thai tea kios karena Square punya quick service yang battle-tested global.

#### Loyverse (international, populer Indonesia)
- Gratis, lalu KDS + multi-store berbayar.
- Open Tickets pattern bagus untuk pre-paid order — kasir simpan order, barista bikin, customer ambil.
- "Take orders in just one click with predefined sets of volumes" — quick add untuk drink presets.

#### Foodics (MENA, beverage focus termasuk Starbucks)
- iPad-based cashier dengan offline mode, KDS, customer display screen.
- Klien: Starbucks, Dunkin Donuts — proven untuk beverage volume tinggi.
- Pelajaran: integrate KDS + customer display sejak awal arsitektur, bukan add-on belakangan.

#### Eats365 / MenuSifu / Chowbus — Bubble-tea-specific
- Highlight: **nested modifier dengan one-tap matrix**.
- Real-time inventory deduction per-topping (Boba habis → opsi tutup otomatis).
- Integration dengan delivery platform.

#### Kopi Kenangan (Indonesia) — non-franchise grab-and-go
- ~800 store di 60+ kota, ~1.5 juta active users di app per Dec 2025.
- Custom-built POS (tidak disclose vendor), tapi pattern observable: counter service + queue ticket + app pre-order.
- App-driven loyalty (membership + points) menggerakkan ~50% sales — pelajaran besar: customer app pre-order adalah lever besar.
- Pattern: customer order di app → ambil di outlet → tunjukkan QR/nomor → barista serve. POS di counter handle in-store order saja.

#### Janji Jiwa / Fore Coffee (Indonesia)
- Counter service system (mirip Starbucks model). ([iReap blog](https://www.ireappos.com/news/en/janji-jiwa-coffee-franchise/))
- JIWA+ customer app untuk order pickup + delivery, lokasi outlet terdekat.
- Studi akademik dokumentasikan Janji Jiwa pakai Moka POS di outlet (995 Comal). Bukti **mainstream POS Indonesia (Moka) viable untuk beverage chain**. ([Untag Semarang](https://jurnal2.untagsmg.ac.id/index.php/soshumdik/article/view/126))

---

## Sintesis: Actionable Recommendations untuk kasir_app

**Arsitektur (Area A):**
1. Tambah tabel `businesses` dengan kolom `type` (`dine_in` / `grab_and_go` / future: `retail`).
2. Tambah kolom `business_id` di semua tabel transaksional. Index `(business_id, created_at)`.
3. Implementasi "tenant context" — `active_business_id` di session, semua repository scope query otomatis.
4. Tabel `user_business_roles` untuk RBAC many-to-many.
5. Owner mode dapat switcher business (Slack/Notion-style). Cashier device locked ke 1 business.
6. Onboarding business kedua: wizard 4 step + opsi clone partial (tax/payment/staff dari business existing).
7. Reporting: per-business utama, owner ringkasan high-level cross-business.

**UI Cashier Grab-and-Go (Area B):**
1. Mode UI berbeda per `business.type`. Thai tea pakai grid besar + sidebar order.
2. Bottom-sheet modifier 1-screen dengan default value pre-selected (1-tap order untuk standar).
3. Queue number auto-increment per business per hari, cetak besar di struk.
4. Kitchen ticket terpisah dari customer receipt. Format bullet-list modifier.
5. Phase 1 pakai dual printer (cashier + barista). Phase 2 migrasi ke KDS tablet.
6. Receipt thermal 58mm sebagai default untuk kios.
7. Future: customer app pre-order (lihat Kopi Kenangan pattern) sebagai growth lever.

---

## Sources (Konsolidasi)

### Area A — Multi-Business / Multi-Outlet
- [Square — Manage multiple locations](https://squareup.com/help/us/en/article/5580-manage-multiple-locations-with-square)
- [Square — Modes per device](https://squareup.com/help/us/en/article/5586-manage-devices-by-location)
- [Square — Dashboard for POS](https://squareup.com/us/en/the-bottom-line/inside-square/updated-square-pos-and-square-dashboard-app)
- [Toast — Multi-Location Management](https://pos.toasttab.com/products/multi-location-management)
- [Toast — Platform overview (groups & locations)](https://doc.toasttab.com/doc/platformguide/platformToastPlatformOverview.html)
- [Toast — How to manage multiple restaurant locations](https://pos.toasttab.com/blog/on-the-line/how-to-manage-multiple-restaurant-locations)
- [Lightspeed — Multi-vertical (retail + restaurant + golf)](https://www.lightspeedhq.com/golf/pos/golf-restaurant/)
- [Lightspeed — User roles & permissions](https://x-series-support.lightspeedhq.com/hc/en-us/articles/25534171377819-Setting-user-roles-and-permissions)
- [Lightspeed — Multistore POS](https://www.lightspeedhq.com/pos/retail/midsize-business-pos/)
- [Loyverse — Multi-store POS](https://loyverse.com/multi-store-pos)
- [Loyverse — Create/manage multiple stores](https://help.loyverse.com/help/how-create-and-manage-multiple)
- [Pawoon — Aplikasi kasir](https://www.pawoon.com/)
- [Pawoon 2.0 — Multi-outlet price setting](https://www.pawoon.com/v2/)
- [Pawoon Help Center — Paket harga](https://www.pawoon-helpcenter.com/mengenal-paket-harga-pawoon-pos)
- [Olsera — Kelola cabang UMKM](https://olsera.com/en/blog/kelola-cabang-umkm-dengan-lebih-mudah-pakai-aplikasi-kasir/563)
- [Olsera POS](https://www.olsera.com/en/pos)
- [iReap POS — Smart cashier untuk UMKM modern](https://www.ireappos.com/news/en/ireap-pos-smart-cashier-app-for-modern-msmes/)
- [Moka POS](https://www.mokapos.com/en)
- [Multi-tenant SaaS DB — 3 approaches (Medium)](https://medium.com/@manu.venugopalan_55726/multi-tenant-saas-a-deep-dive-into-database-design-approaches-3a01fe0c083b)
- [Multi-tenant DB patterns (Bytebase)](https://www.bytebase.com/blog/multi-tenant-database-architecture-patterns-explained/)
- [WorkOS — SaaS multi-tenant architecture](https://workos.com/blog/developers-guide-saas-multi-tenant-architecture)
- [Multi-tenant database design patterns 2026 (daily.dev)](https://daily.dev/blog/multi-tenant-database-design-patterns-2024/)
- [Turso — Multi-tenant SQLite SaaS](https://turso.tech/blog/creating-a-multitenant-saas-service-with-turso-remix-and-drizzle-6205cf47)
- [Drizzle multi-tenant POC (GitHub)](https://gist.github.com/gyopiazza/70919f2c97a01d1b9897057d11fb9933)
- [Eposly — RBAC for multi-store retail](https://eposly.io/blogs-insights/securing-multi-store-retail-with-role-based-pos-permissions/)
- [Acid POS — User permissions](https://www.acidpos.com/features/user-permissions/)
- [Yonkers Times — Fixing data blind spot in multi-location](https://yonkerstimes.com/fixing-the-data-blind-spot-why-multi-location-reporting-fails-without-one-dashboard/)
- [DualEntry — Multi-entity accounting](https://www.dualentry.com/scale/multi-entity-accounting-software)
- [Agiliron — POS Channel Duplicate](https://learn.agiliron.com/docs/pos-channel-duplicate)
- [CAKE POS — Onboarding Wizard](https://university.cake.net/support/s/article/POS-Onboarding-Wizard)
- [Slack — Workspace switching mobile](https://slack.com/help/articles/1500002200741-Switch-between-workspaces)
- [Notion — Workspaces on mobile](https://www.notion.com/help/workspaces-on-mobile)
- [Jon Moore — Account & app switcher design patterns](https://medium.com/ux-power-tools/ways-to-design-account-switchers-app-switchers-743e05372ede)

### Area B — Grab-and-Go Beverage
- [Square — Quick service POS](https://squareup.com/us/en/restaurants/quick-service)
- [Square — Modes (Full/Quick/Bar)](https://squareup.com/help/us/en/article/8458-use-modes-with-square-point-of-sale)
- [Square — Restaurant POS](https://squareup.com/us/en/point-of-sale/restaurants)
- [Square — KDS](https://squareup.com/us/en/point-of-sale/restaurants/kitchen-display-system)
- [Toast — Best QSR POS features](https://pos.toasttab.com/blog/best-quick-service-pos-systems)
- [Lightspeed — POS layout design](https://o-series-support.lightspeedhq.com/hc/en-us/articles/31329442916891-Design-your-POS-look-and-layout)
- [Lightspeed — Kitchen Display System](https://www.lightspeedhq.com/pos/restaurant/kitchen-display-system/)
- [Loyverse — Bar & Pub POS](https://loyverse.com/bar-pos)
- [Loyverse — Open Tickets](https://help.loyverse.com/help/open-tickets)
- [Loyverse — Kitchen Display](https://help.loyverse.com/help/kitchen-display-system)
- [Loyverse — Custom orders for coffee & drinks (forum)](https://loyverse.town/topic/7551-how-can-i-manage-custom-orders-for-coffee-and-drinks/)
- [Foodics — RMS & POS for MENA F&B](https://www.foodics.com/)
- [Foodics POS system overview](https://www.foodics.com/foodics-pos-system-manage-your-restaurant-like-never-before/)
- [Eats365 — Bubble tea POS must-haves](https://www.eats365pos.com/my/blog/post/bubble-tea-pos-must-haves)
- [Eats365 — Hidden risks of generic POS for bubble tea](https://www.eats365pos.com/blog/post/hidden-risks-generic-pos-bubble-tea)
- [Ginger — Best POS for boba shops, nested modifiers](https://www.gingerserve.com/guides/best-pos-for-boba-tea-shops)
- [MenuSifu — POS for bubble tea shop](https://www.menusifu.com/blog/pos-system-for-bubble-tea-shop)
- [Chowbus — Bubble tea POS](https://www.chowbus.com/blog/pos-system-for-bubble-tea-shop)
- [Sharetea — Customize your bubble tea order](https://www.1992sharetea.com/news/how-to-customize-your-bubble-tea-order-at-sharetea)
- [Joe Coffee — Why coffee shop needs KDS](https://joe.coffee/blog/posts/coffee-shop-kds-system/)
- [Joe Coffee blog — KDS](https://blog.joe.coffee/4-reasons-why-your-coffee-shop-needs-a-kitchen-display-system-kds)
- [QueueBee — Queue management system](https://www.queuebeesolution.com/queue-management-system.php)
- [Queue Number Bluetooth Printer (Play Store, Indonesia)](https://play.google.com/store/apps/details?id=com.hardiyosodev.queue_number_bluetooth_printer)
- [OrderReady mobile app](https://www.orderready.app/)
- [SimpleTexting — SMS templates "order ready"](https://simpletexting.com/blog/send-a-text-message-when-customers-food-is-ready/)
- [INFI — Boba beverage self-order kiosk](https://infi.us/boba-beverage/)
- [HPRT — Why choose 58mm thermal printer](https://www.hprt.com/blog/Why-Choose-a-58mm-Receipt-Printer-for-Your-Small-Retail-Businesses-and-Takeaway-Shops.html)
- [iReap — Thermal printers guide](https://www.ireappos.com/news/en/thermal-printers-types-and-recommendations/)
- [Nutapos — Printer kasir untuk usaha minuman](https://nutapos.com/post/fungsi-printer-kasir-untuk-usaha-minuman/)
- [Kopi Kenangan — Coffee culture (Intelligence Coffee)](https://intelligence.coffee/2022/10/kopi-kenangan-indonesia-coffee-culture/)
- [Kopi Kenangan — VnExpress story](https://e.vnexpress.net/news/business/companies/from-local-stall-to-one-of-southeast-asia-s-largest-coffee-chains-the-story-behind-indonesia-s-kopi-kenangan-5064645.html)
- [iReap — Janji Jiwa franchise](https://www.ireappos.com/news/en/janji-jiwa-coffee-franchise/)
- [Studi akademik — Janji Jiwa pakai Moka POS](https://jurnal2.untagsmg.ac.id/index.php/soshumdik/article/view/126)
- [JIWA+ Customer App (Play Store)](https://play.google.com/store/apps/details?id=com.jiwa.jiwagroup)

### Cross-cutting (UX & general POS UX)
- [Dev.Pro — 10 POS UX tactics](https://dev.pro/insights/designing-a-pos-system-ten-user-experience-tactics-that-improve-usability/)
- [AgenteStudio — POS design principles retail & restaurants](https://agentestudio.com/blog/design-principles-pos-interface)
- [TryPerDiem — Square multi-location for small QSR chains](https://www.tryperdiem.com/post/how-square-pos-simplifies-multi-location-operations-for-small-qsr-chains)
