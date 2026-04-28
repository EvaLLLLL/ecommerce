package com.ecommerce.shoppingcartservice.service;

import com.ecommerce.shoppingcartservice.config.ServicesConfig;
import com.ecommerce.shoppingcartservice.model.ShoppingCart;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.core.JacksonException;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

/**
 * Client for the distributed KV database. Handles cart CRUD, order persistence, and transaction
 * boundary calls.
 * <p>
 * Key format: cart:{cart_id}   → JSON-serialized ShoppingCart order:{order_id} → JSON summary of a
 * completed order
 */
@Service
public class KvDatabaseClient {

  private static final Logger log = LoggerFactory.getLogger(KvDatabaseClient.class);
  private static final String CART_PREFIX = "cart:";
  private static final String ORDER_PREFIX = "order:";
  private static final String ACTIVE_CART_PREFIX = "active-cart:";

  private final ServicesConfig config;
  private final RestTemplate restTemplate;
  private final ObjectMapper objectMapper;

  public KvDatabaseClient(ServicesConfig config, RestTemplate restTemplate,
      ObjectMapper objectMapper) {
    this.config = config;
    this.restTemplate = restTemplate;
    this.objectMapper = objectMapper;
  }

  // ── Cart CRUD ─────────────────────────────────────────────────────────────

  public void saveCart(ShoppingCart cart) {
    put(CART_PREFIX + cart.getCart_id(), serialize(cart));
  }

  public Optional<ShoppingCart> getCart(int cartId) {
    return get(CART_PREFIX + cartId).map(json -> deserialize(json, ShoppingCart.class));
  }

  public void saveActiveCartId(int customerId, int cartId) {
    put(ACTIVE_CART_PREFIX + customerId, String.valueOf(cartId));
  }

  public Optional<Integer> getActiveCartId(int customerId) {
    return get(ACTIVE_CART_PREFIX + customerId)
        .filter(v -> !v.isBlank())
        .map(Integer::parseInt);
  }

  public void clearActiveCart(int customerId) {
    put(ACTIVE_CART_PREFIX + customerId, "");
  }

  // ── Order persistence ─────────────────────────────────────────────────────

  /**
   * Persists a completed order. The order record is a JSON summary of the cart at checkout time.
   * Returns the order ID (same as cart ID for simplicity).
   */
  public int commitOrder(ShoppingCart cart, String creditCardNumber) {
    int orderId = cart.getCart_id();
    Map<String, Object> orderRecord = Map.of(
        "order_id", orderId,
        "customer_id", cart.getCustomer_id(),
        "items", cart.getItems(),
        "credit_card_last4", creditCardNumber.substring(creditCardNumber.length() - 4)
    );
    put(ORDER_PREFIX + orderId, serialize(orderRecord));
    return orderId;
  }

  // ── Transaction endpoints ─────────────────────────────────────────────────

  /**
   * Starts a transaction and returns the transaction_id assigned by the KV database.
   */
  public String beginTransaction() {
    try {
      ResponseEntity<Map> response = restTemplate.postForEntity(
          config.getKvDatabaseUrl() + "/db/begin_transaction", null, Map.class);
      if (response.getBody() != null) {
        return (String) response.getBody().get("transaction_id");
      }
      throw new RuntimeException("begin_transaction returned no transaction_id");
    } catch (Exception e) {
      log.error("begin_transaction failed: {}", e.getMessage());
      throw new RuntimeException("KV database transaction error", e);
    }
  }

  public void endTransaction(String transactionId) {
    try {
      Map<String, String> body = Map.of("transaction_id", transactionId);
      restTemplate.postForEntity(
          config.getKvDatabaseUrl() + "/db/end_transaction",
          new HttpEntity<>(body), Map.class);
    } catch (Exception e) {
      log.error("end_transaction failed for tx {}: {}", transactionId, e.getMessage());
    }
  }

  public void abortTransaction(String transactionId) {
    try {
      Map<String, String> body = Map.of("transaction_id", transactionId);
      restTemplate.postForEntity(
          config.getKvDatabaseUrl() + "/db/abort_transaction",
          new HttpEntity<>(body), Map.class);
    } catch (Exception e) {
      log.error("abort_transaction failed for tx {}: {}", transactionId, e.getMessage());
    }
  }

  // ── Private KV helpers ────────────────────────────────────────────────────

  private void put(String key, String value) {
    Map<String, String> body = Map.of("key", key, "value", value);
    try {
      restTemplate.exchange(
          config.getKvDatabaseUrl() + "/kv",
          HttpMethod.PUT, new HttpEntity<>(body), Map.class);
    } catch (Exception e) {
      log.error("KV PUT failed for key '{}': {}", key, e.getMessage());
      throw new RuntimeException("KV database write failed", e);
    }
  }

  private Optional<String> get(String key) {
    try {
      ResponseEntity<Map> response = restTemplate.getForEntity(
          config.getKvDatabaseUrl() + "/kv?key=" + key, Map.class);
      if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
        Object value = response.getBody().get("value");
        return Optional.ofNullable(value).map(Object::toString);
      }
      return Optional.empty();
    } catch (HttpClientErrorException.NotFound e) {
      return Optional.empty();
    } catch (Exception e) {
      log.error("KV GET failed for key '{}': {}", key, e.getMessage());
      throw new RuntimeException("KV database read failed", e);
    }
  }

  private String serialize(Object obj) {
    try {
      return objectMapper.writeValueAsString(obj);
    } catch (JacksonException e) {
      throw new RuntimeException("Serialization failed", e);
    }
  }

  private <T> T deserialize(String json, Class<T> type) {
    try {
      return objectMapper.readValue(json, type);
    } catch (JacksonException e) {
      throw new RuntimeException("Deserialization failed", e);
    }
  }
}
