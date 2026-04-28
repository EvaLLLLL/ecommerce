package com.ecommerce.dataloader;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Batch loads 1,000 products into the Product Service before load testing begins.
 * <p>
 * Configuration (via environment variables or JVM args): PRODUCT_SERVICE_URL  – base URL of the
 * Product Service (default: http://localhost:8080) PRODUCT_COUNT        – number of products to
 * load (default: 1000) THREAD_COUNT         – number of concurrent loader threads (default: 10)
 * <p>
 * Run: mvn package -pl data-loader -q java -jar data-loader/target/data-loader-1.0-SNAPSHOT.jar or:
 * PRODUCT_SERVICE_URL=http://<alb-url> mvn exec:java -pl data-loader
 */
public class DataLoader {

  public static void main(String[] args) throws InterruptedException {
    String productServiceUrl = getEnv("PRODUCT_SERVICE_URL", "http://localhost:8080");
    int productCount = Integer.parseInt(getEnv("PRODUCT_COUNT", "1000"));
    int threadCount = Integer.parseInt(getEnv("THREAD_COUNT", "10"));

    System.out.printf("Loading %d products into %s using %d threads%n",
        productCount, productServiceUrl, threadCount);

    ProductGenerator generator = new ProductGenerator();
    ProductApiClient client = new ProductApiClient(productServiceUrl);
    AtomicInteger successCount = new AtomicInteger(0);
    AtomicInteger failCount = new AtomicInteger(0);

    ExecutorService executor = Executors.newFixedThreadPool(threadCount);
    List<Future<?>> futures = new ArrayList<>();
    long startTime = System.currentTimeMillis();

    for (int i = 0; i < productCount; i++) {
      final Map<String, Object> productData = generator.generate();
      futures.add(executor.submit(() -> {
        int productId = client.createProduct(productData);
        if (productId > 0) {
          int done = successCount.incrementAndGet();
          if (done % 100 == 0) {
            System.out.printf("  Loaded %d / %d products...%n", done, productCount);
          }
        } else {
          failCount.incrementAndGet();
        }
      }));
    }

    // Wait for all tasks to complete
    for (Future<?> f : futures) {
      try {
        f.get();
      } catch (Exception e) {
        System.err.println("Task error: " + e.getMessage());
      }
    }

    executor.shutdown();
    long elapsed = System.currentTimeMillis() - startTime;

    System.out.println("=== Data Load Complete ===");
    System.out.printf("  Successful: %d%n", successCount.get());
    System.out.printf("  Failed:     %d%n", failCount.get());
    System.out.printf("  Elapsed:    %.2f seconds%n", elapsed / 1000.0);
    System.out.printf("  Throughput: %.1f products/sec%n",
        successCount.get() / (elapsed / 1000.0));
  }

  private static String getEnv(String key, String defaultValue) {
    String value = System.getenv(key);
    return (value != null && !value.isBlank()) ? value : defaultValue;
  }
}
