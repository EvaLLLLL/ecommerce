package com.ecommerce.shoppingcartservice.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.JacksonJsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.lang.NonNull;

@Configuration
public class RabbitMqConfig {

  private static final Logger log = LoggerFactory.getLogger(RabbitMqConfig.class);

  @Value("${warehouse.queue.name}")
  private String queueName;

  /**
   * Declares the durable queue; idempotent — safe to call even if the Warehouse already declared
   * it.
   */
  @Bean
  public Queue shipQueue() {
    return new Queue(queueName, true);
  }

  @Bean
  public MessageConverter jsonMessageConverter() {
    return new JacksonJsonMessageConverter();
  }

  /**
   * RabbitTemplate with Publisher Confirms enabled (as required by Assignment 3). The SCS waits for
   * broker acknowledgement before considering the publish successful. Note:
   * spring.rabbitmq.publisher-confirm-type=correlated must be set in properties.
   */
  @Bean
  public RabbitTemplate rabbitTemplate(@NonNull ConnectionFactory connectionFactory,
      @NonNull MessageConverter jsonMessageConverter) {
    RabbitTemplate template = new RabbitTemplate(connectionFactory);
    template.setMessageConverter(jsonMessageConverter);
    template.setConfirmCallback((correlationData, ack, cause) -> {
      if (!ack) {
        log.error("Ship message not confirmed by RabbitMQ broker: {}", cause);
      }
    });
    return template;
  }
}
