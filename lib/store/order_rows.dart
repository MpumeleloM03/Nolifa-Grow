import 'package:ubuntu_core/ubuntu_core.dart' show Order, OrderStatus;

/// Newest orders first.
List<Order> sortedFarmOrders(List<Order> farmOrders) =>
    [...farmOrders]..sort((a, b) => b.placed.compareTo(a.placed));

/// The orders list with its group labels: new orders first under "New orders",
/// the rest under "Earlier orders". Labels only appear when both groups exist.
List<Object> orderRows(List<Order> sorted) {
  final fresh = [
    for (final o in sorted)
      if (o.status == OrderStatus.newOrder) o
  ];
  final earlier = [
    for (final o in sorted)
      if (o.status != OrderStatus.newOrder) o
  ];
  return [
    if (fresh.isNotEmpty && earlier.isNotEmpty) 'New orders',
    ...fresh,
    if (fresh.isNotEmpty && earlier.isNotEmpty) 'Earlier orders',
    ...earlier,
  ];
}
