package com.ecommerce.shoppingcartservice.service;

import com.ecommerce.shoppingcartservice.config.ServicesConfig;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

@Service
public class ProductServiceClient {

  private static final Logger log = LoggerFactory.getLogger(ProductServiceClient.class);

  private final ServicesConfig config;
  private final RestTemplate restTemplate;

  public ProductServiceClient(ServicesConfig config, RestTemplate restTemplate) {
    this.config = config;
    this.restTemplate = restTemplate;
  }

  /**
   * Fetches a product's weight from the Product Service. Returns -1 if the product is not found.
   */
  public int getProductWeight(int productId) {
    try {
      ResponseEntity<Map> response = restTemplate.getForEntity(
          config.getProductServiceUrl() + "/products/" + productId, Map.class);
      if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
        Object weight = response.getBody().get("weight");
        return weight != null ? ((Number) weight).intValue() : 0;
      }
      return -1;
    } catch (HttpClientErrorException.NotFound e) {
      return -1;
    } catch (Exception e) {
      log.error("Failed to fetch product {}: {}", productId, e.getMessage());
      throw new RuntimeException("Product Service unavailable", e);
    }
  }
}
