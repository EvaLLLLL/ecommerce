package com.ecommerce.shoppingcartservice.model;

import java.util.ArrayList;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Message published to the RabbitMQ ship queue after a successful checkout. Must match the
 * ShipMessage schema expected by the Warehouse consumer.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ShipMessage {

  private int order_id;
  private List<CartItem> items = new ArrayList<>();
}
