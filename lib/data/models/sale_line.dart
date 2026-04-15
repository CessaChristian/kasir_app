class SaleLine {
  final String productId;
  final String productName;
  final int qty;
  final int priceAtSale;
  final bool trackStock;

  SaleLine({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.priceAtSale,
    required this.trackStock,
  });

  int get subtotal => qty * priceAtSale;
}
