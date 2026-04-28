package com.ecommerce.kvdatabase.service;

import com.ecommerce.kvdatabase.model.KvEntry;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class FollowerService {

  @Autowired
  private StorageService storageService;

  public void put(String key, String value, int version) {
    storageService.putLocal(key, value, version);
  }

  public KvEntry get(String key) {
    return storageService.getLocal(key).orElse(null);
  }
}