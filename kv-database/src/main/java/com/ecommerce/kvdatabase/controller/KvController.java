package com.ecommerce.kvdatabase.controller;

import java.util.Map;
import com.ecommerce.kvdatabase.model.KvEntry;
import com.ecommerce.kvdatabase.model.KvRequest;
import com.ecommerce.kvdatabase.config.NodeConfig;
import com.ecommerce.kvdatabase.service.FollowerService;
import com.ecommerce.kvdatabase.service.LeaderService;
import com.ecommerce.kvdatabase.service.LeaderlessService;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/kv")
public class KvController {

  private static final Logger log = LoggerFactory.getLogger(KvController.class);

  @Autowired
  private NodeConfig nodeConfig;

  @Autowired
  private LeaderService leaderService;

  @Autowired
  private FollowerService followerService;

  @Autowired
  private LeaderlessService leaderlessService;

  @PutMapping
  public ResponseEntity<?> put(@Valid @RequestBody KvRequest request) {
    try {
      if ("leaderless".equalsIgnoreCase(nodeConfig.getRole())) {
        int version = leaderlessService.handleClientWrite(request.key(), request.value());
        return ResponseEntity.status(HttpStatus.CREATED).body(
            Map.of("key", request.key(), "version", version, "coordinatorUrl",
                nodeConfig.getNodeSelfUrl()));
      } else if (nodeConfig.isLeader()) {
        int version = leaderService.put(request.key(), request.value());
        return ResponseEntity.status(HttpStatus.CREATED)
            .body(Map.of("key", request.key(), "version", version));
      } else {
        followerService.put(request.key(), request.value(), request.version());
        return ResponseEntity.status(HttpStatus.CREATED)
            .body(Map.of("key", request.key(), "version", request.version()));
      }

    } catch (RuntimeException e) {
      log.error("Error during PUT: {}", e.getMessage());
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
          .body(Map.of("error", "SERVICE_UNAVAILABLE", "message", e.getMessage()));
    }
  }

  @GetMapping("/local_read")
  public ResponseEntity<?> localRead(@RequestParam String key) {
    try {
      KvEntry entry = followerService.get(key);
      if (entry == null) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
            .body(Map.of("error", "NOT_FOUND", "message", "Key not found: " + key));
      }
      return ResponseEntity.ok(
          Map.of("key", key, "value", entry.getValue(), "version", entry.getVersion(), "timestamp",
              entry.getTimestamp()));
    } catch (RuntimeException e) {
      log.error("Error during local_read: {}", e.getMessage());
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
          .body(Map.of("error", "SERVICE_UNAVAILABLE", "message", e.getMessage()));
    }
  }

  @GetMapping
  public ResponseEntity<?> get(@RequestParam String key) {
    if (key == null || key.isBlank()) {
      return ResponseEntity.badRequest()
          .body(Map.of("error", "INVALID_INPUT", "message", "Key cannot be empty"));
    }

    try {
      KvEntry entry;
      if ("leaderless".equalsIgnoreCase(nodeConfig.getRole())) {
        // Leaderless R=1: return local value only
        entry = leaderlessService.handleRead(key).orElse(null);
      } else if (nodeConfig.isLeader()) {
        entry = leaderService.get(key);
      } else {
        entry = followerService.get(key);
      }

      if (entry == null) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
            .body(Map.of("error", "NOT_FOUND", "message", "Key not found: " + key));
      }

      return ResponseEntity.ok(
          Map.of("key", key, "value", entry.getValue(), "version", entry.getVersion(), "timestamp",
              entry.getTimestamp()));
    } catch (RuntimeException e) {
      log.error("Error during GET: {}", e.getMessage());
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
          .body(Map.of("error", "SERVICE_UNAVAILABLE", "message", e.getMessage()));
    }
  }

  // ── Internal: PUT /kv/internal/kv ────────────────────────────────────
  // Called only by other nodes during Leaderless write propagation

  @PutMapping("/internal/kv")
  public ResponseEntity<?> internalPut(@Valid @RequestBody KvRequest request) {
    try {
      leaderlessService.handleInternalWrite(request.key(), request.value(), request.version())
      ;
      return ResponseEntity.status(HttpStatus.CREATED).build();
    } catch (RuntimeException e) {
      log.error("Error during internal PUT: {}", e.getMessage());
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
          .body(Map.of("error", "SERVICE_UNAVAILABLE", "message", e.getMessage()));
    }
  }

}
