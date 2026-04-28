package com.ecommerce.shoppingcartservice.config;

import lombok.Getter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.restclient.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;
import java.time.Duration;

@Getter
@Configuration
public class ServicesConfig {

  @Value("${product.service.url:http://localhost:8080}")
  private String productServiceUrl;

  @Value("${warehouse.service.url:http://localhost:8083}")
  private String warehouseServiceUrl;

  @Value("${cca.service.url:http://localhost:8081}")
  private String ccaServiceUrl;

  @Value("${kv.database.url:http://localhost:8084}")
  private String kvDatabaseUrl;

  @Bean
  public RestTemplate restTemplate(RestTemplateBuilder builder) {
    return builder
        .connectTimeout(Duration.ofSeconds(5))
        .readTimeout(Duration.ofSeconds(15))
        .build();
  }
}
