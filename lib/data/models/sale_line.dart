class SaleLine {
  final String productId;
  final String productName;
  final int qty;
  final int priceAtSale;
  final String? notes;

  SaleLine({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.priceAtSale,
    this.notes,
  });

  /// Satu-satunya rumus subtotal di aplikasi — dipakai keranjang untuk total
  /// yang tampil di layar dan `createSale` untuk total yang tersimpan.
  int get subtotal => qty * priceAtSale;

  SaleLine copyWith({int? qty}) => SaleLine(
        productId: productId,
        productName: productName,
        qty: qty ?? this.qty,
        priceAtSale: priceAtSale,
        notes: notes,
      );
}
