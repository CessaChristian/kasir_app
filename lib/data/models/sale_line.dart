class SaleLine {
  final String productId;
  final String productName;
  final int qty;
  final int priceAtSale;
  final bool trackStock;
  final String? notes;

  SaleLine({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.priceAtSale,
    required this.trackStock,
    this.notes,
  });

  int get subtotal => qty * priceAtSale;
}
