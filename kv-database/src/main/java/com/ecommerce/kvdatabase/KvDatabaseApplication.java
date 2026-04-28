package com.ecommerce.kvdatabase;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "com.ecommerce")
public class KvDatabaseApplication {

  public static void main(String[] args) {
    SpringApplication.run(KvDatabaseApplication.class, args);
  }

}
