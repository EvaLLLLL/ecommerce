package com.ecommerce.productservice.config;

import lombok.Getter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.boot.restclient.RestTemplateBuilder;
import org.springframework.web.client.RestTemplate;
import java.time.Duration;

@Getter
@Configuration
public class KvDatabaseConfig {

  /**
   * Base URL of the KV database node used for product storage. Products have a high read / low
   * write ratio, so this should point to a Leader-Follower database configured with W=5, R=1:
   * strong-consistency writes, fast single-node reads.
   * <p>
   * Override at runtime: KV_DATABASE_URL=http://<leader-ip>:8084
   */
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
