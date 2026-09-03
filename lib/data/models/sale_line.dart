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

  int get subtotal => qty * priceAtSale;
}
