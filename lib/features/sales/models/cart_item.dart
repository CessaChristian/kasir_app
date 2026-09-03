class CartItem {
  final String productId;
  final String productName;
  final int pricePerUnit;
  final int qty;
  final String? notes;

  CartItem({
    required this.productId,
    required this.productName,
    required this.pricePerUnit,
    required this.qty,
    this.notes,
  });

  int get subtotal => pricePerUnit * qty;

  CartItem copyWith({int? qty, String? notes}) {
    return CartItem(
      productId: productId,
      productName: productName,
      pricePerUnit: pricePerUnit,
      qty: qty ?? this.qty,
      notes: notes ?? this.notes,
    );
  }
}
