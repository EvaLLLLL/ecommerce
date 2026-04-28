package com.ecommerce.productservice.service;

import com.ecommerce.productservice.config.KvDatabaseConfig;
import com.ecommerce.productservice.model.CreateProductRequest;
import com.ecommerce.productservice.model.Product;
import java.util.concurrent.atomic.AtomicInteger;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.core.JacksonException;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

/**
 * Business logic for product management.
 * <p>
 * Products are persisted in the distributed KV database. Key format: "product:{product_id}"  (e.g.
 * "product:42") Value: JSON-encoded Product object
 */
@Service
public class ProductService {

  private static final Logger log = LoggerFactory.getLogger(ProductService.class);
  private static final String KEY_PREFIX = "product:";

  private final KvDatabaseConfig kvConfig;
  private final RestTemplate restTemplate;
  private final ObjectMapper objectMapper;

  // Starts at 1; in a real system this would be replaced by a distributed counter
  private final AtomicInteger idCounter = new AtomicInteger(1);

  public ProductService(KvDatabaseConfig kvConfig, RestTemplate restTemplate,
      ObjectMapper objectMapper) {
    this.kvConfig = kvConfig;
    this.restTemplate = restTemplate;
    this.objectMapper = objectMapper;
  }

  /**
   * Creates a product, assigns a product_id, and persists it to the KV database.
   *
   * @return the assigned product_id
   */
  public int createProduct(CreateProductRequest request) {
    int productId = idCounter.getAndIncrement();
    Product product = new Product(
        productId,
        request.getSku(),
        request.getManufacturer(),
        request.getCategory_id(),
        request.getWeight(),
        request.getSome_other_id()
    );

    String value = serialize(product);
    writeToKv(KEY_PREFIX + productId, value);
    return productId;
  }

  /**
   * Retrieves a product by ID from the KV database.
   *
   * @return the product, or empty if not found
   */
  public Optional<Product> getProduct(int productId) {
    return readFromKv(KEY_PREFIX + productId)
        .map(this::deserialize);
  }

  // ── KV database access ────────────────────────────────────────────────────

  private void writeToKv(String key, String value) {
    Map<String, String> body = Map.of("key", key, "value", value);
    HttpEntity<Map<String, String>> request = new HttpEntity<>(body);
    try {
      restTemplate.exchange(
          kvConfig.getKvDatabaseUrl() + "/kv",
          HttpMethod.PUT, request, Map.class);
    } catch (Exception e) {
      log.error("KV write failed for key '{}': {}", key, e.getMessage());
      throw new RuntimeException("Failed to persist product to database", e);
    }
  }

  private Optional<String> readFromKv(String key) {
    try {
      var response = restTemplate.getForEntity(
          kvConfig.getKvDatabaseUrl() + "/kv?key=" + key, Map.class);
      if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
        Object value = response.getBody().get("value");
        return Optional.ofNullable(value).map(Object::toString);
      }
      return Optional.empty();
    } catch (HttpClientErrorException.NotFound e) {
      return Optional.empty();
    } catch (Exception e) {
      log.error("KV read failed for key '{}': {}", key, e.getMessage());
      throw new RuntimeException("Failed to read product from database", e);
    }
  }

  // ── JSON helpers ──────────────────────────────────────────────────────────

  private String serialize(Product product) {
    try {
      return objectMapper.writeValueAsString(product);
    } catch (JacksonException e) {
      throw new RuntimeException("Failed to serialize product", e);
    }
  }

  private Product deserialize(String json) {
    try {
      return objectMapper.readValue(json, Product.class);
    } catch (JacksonException e) {
      throw new RuntimeException("Failed to deserialize product", e);
    }
  }
}
