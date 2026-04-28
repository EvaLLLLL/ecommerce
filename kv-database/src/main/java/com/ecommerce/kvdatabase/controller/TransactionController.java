package com.ecommerce.kvdatabase.controller;

import com.ecommerce.kvdatabase.model.TransactionRequest;
import jakarta.validation.Valid;
import java.util.Map;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Simulated transaction endpoints. Per assignment requirement, these only print log messages —
 * there is no real 2PC implementation.
 */
@RestController
@RequestMapping("/db")
public class TransactionController {

  private static final Logger log = LoggerFactory.getLogger(TransactionController.class);

  /**
   * POST /db/begin_transaction — returns a new transaction_id.
   */
  @PostMapping("/begin_transaction")
  public ResponseEntity<Map<String, String>> beginTransaction() {
    String txId = UUID.randomUUID().toString();
    log.info("BEGIN TRANSACTION: {}", txId);
    return ResponseEntity.ok(Map.of("transaction_id", txId));
  }

  /**
   * POST /db/end_transaction — commits (logs) the transaction.
   */
  @PostMapping("/end_transaction")
  public ResponseEntity<Map<String, String>> endTransaction(
      @Valid @RequestBody TransactionRequest request) {
    log.info("COMMIT TRANSACTION: {}", request.transaction_id());
    return ResponseEntity.ok(
        Map.of("status", "committed", "transaction_id", request.transaction_id()));
  }

  /**
   * POST /db/abort_transaction — rolls back (logs) the transaction.
   */
  @PostMapping("/abort_transaction")
  public ResponseEntity<Map<String, String>> abortTransaction(
      @Valid @RequestBody TransactionRequest request) {
    log.info("ABORT TRANSACTION: {}", request.transaction_id());
    return ResponseEntity.ok(
        Map.of("status", "aborted", "transaction_id", request.transaction_id()));
  }
}
