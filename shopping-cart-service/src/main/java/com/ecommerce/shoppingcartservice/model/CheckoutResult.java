package com.ecommerce.shoppingcartservice.model;

public record CheckoutResult(Status status, String message, int orderId) {

  public enum Status {SUCCESS, NOT_FOUND, BAD_REQUEST, OUT_OF_STOCK, PAYMENT_DECLINED}

  public static CheckoutResult success(int orderId) {
    return new CheckoutResult(Status.SUCCESS, "", orderId);
  }

  public static CheckoutResult notFound(String msg) {
    return new CheckoutResult(Status.NOT_FOUND, msg, 0);
  }

  public static CheckoutResult badRequest(String msg) {
    return new CheckoutResult(Status.BAD_REQUEST, msg, 0);
  }

  public static CheckoutResult outOfStock(String msg) {
    return new CheckoutResult(Status.OUT_OF_STOCK, msg, 0);
  }

  public static CheckoutResult paymentDeclined(String msg) {
    return new CheckoutResult(Status.PAYMENT_DECLINED, msg, 0);
  }
}
