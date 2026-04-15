/// CartItem model untuk merepresentasikan item di shopping cart
class CartItem {
  final String productId;
  final String productName;
  final int pricePerUnit;
  final int qty;

  CartItem({
    required this.productId,
    required this.productName,
    required this.pricePerUnit,
    required this.qty,
  });

  int get subtotal => pricePerUnit * qty;
}
