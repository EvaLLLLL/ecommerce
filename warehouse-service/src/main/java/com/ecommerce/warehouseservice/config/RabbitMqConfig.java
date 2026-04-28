package com.ecommerce.warehouseservice.config;

import org.springframework.amqp.core.Queue;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.support.converter.JacksonJsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMqConfig {

  @Value("${warehouse.queue.name}")
  private String queueName;

  @Value("${warehouse.listener.auto-startup}")
  private boolean listenerAutoStartup;

  @Value("${warehouse.consumer-count}")
  private int consumerCount;

  @Value("${warehouse.max-consumer-count}")
  private int maxConsumerCount;

  @Value("${warehouse.prefetch-count}")
  private int prefetchCount;

  /**
   * Durable queue so messages survive a RabbitMQ restart. The Shopping Cart Service (publisher)
   * must declare the same queue name.
   */
  @Bean
  public Queue shipQueue() {
    return new Queue(queueName, true);
  }

  /**
   * JSON converter so ShipMessage objects are serialized/deserialized automatically.
   */
  @Bean
  public MessageConverter jsonMessageConverter() {
    return new JacksonJsonMessageConverter();
  }

  /**
   * Listener container with manual acknowledgements enabled. The consumer acks only after the
   * message has been fully processed, preventing message loss if the Warehouse crashes
   * mid-processing.
   * <p>
   * concurrentConsumers/maxConcurrentConsumers: tuned so that the consumption rate roughly matches
   * the SCS publish rate, keeping the queue length near zero.
   */
  @Bean
  public SimpleRabbitListenerContainerFactory rabbitListenerContainerFactory(
      ConnectionFactory connectionFactory, MessageConverter jsonMessageConverter) {
    SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
    factory.setConnectionFactory(connectionFactory);
    factory.setMessageConverter(jsonMessageConverter);
    factory.setAcknowledgeMode(org.springframework.amqp.core.AcknowledgeMode.MANUAL);
    factory.setPrefetchCount(prefetchCount);
    factory.setConcurrentConsumers(consumerCount);
    factory.setMaxConcurrentConsumers(maxConsumerCount);
    factory.setAutoStartup(listenerAutoStartup);
    return factory;
  }
}
