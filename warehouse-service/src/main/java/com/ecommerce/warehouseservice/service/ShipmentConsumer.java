package com.ecommerce.warehouseservice.service;

import com.ecommerce.warehouseservice.model.ShipMessage;
import com.rabbitmq.client.Channel;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.support.AmqpHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;
import java.io.IOException;

/**
 * Asynchronous RabbitMQ consumer that processes ship requests sent by the Shopping Cart Service
 * after a successful checkout.
 * <p>
 * Concurrency is controlled by the SimpleRabbitListenerContainerFactory configured in
 * RabbitMqConfig (16–64 concurrent consumers), keeping the queue depth close to zero.
 */
@Component
public class ShipmentConsumer {

  private static final Logger log = LoggerFactory.getLogger(ShipmentConsumer.class);

  private final InventoryService inventoryService;

  public ShipmentConsumer(InventoryService inventoryService) {
    this.inventoryService = inventoryService;
  }

  @RabbitListener(queues = "${warehouse.queue.name}", containerFactory = "rabbitListenerContainerFactory")
  public void handleShipMessage(ShipMessage message, Channel channel,
      @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag) throws IOException {
    try {
      log.info("Received ship order {} with {} line items", message.getOrder_id(),
          message.getItems().size());
      inventoryService.shipOrder(message.getOrder_id(), message.getItems());
      // Acknowledge only after successful processing
      channel.basicAck(deliveryTag, false);
    } catch (Exception e) {
      log.error("Failed to process ship order {}: {}", message.getOrder_id(), e.getMessage());
      // Nack and requeue so the message is not lost
      channel.basicNack(deliveryTag, false, true);
    }
  }
}
