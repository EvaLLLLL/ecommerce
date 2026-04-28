package com.ecommerce.shoppingcartservice.model;

public record AddItemResult(Status status, String message, Integer cartId) {

  public enum Status {OK, NOT_FOUND, INSUFFICIENT_STOCK, BAD_REQUEST}

  public static AddItemResult ok(int cartId) {
    return new AddItemResult(Status.OK, "", cartId);
  }

  public static AddItemResult notFound(String msg) {
    return new AddItemResult(Status.NOT_FOUND, msg, null);
  }

  public static AddItemResult notFound(String msg, int cartId) {
    return new AddItemResult(Status.NOT_FOUND, msg, cartId);
  }

  public static AddItemResult insufficientStock(String msg, int cartId) {
    return new AddItemResult(Status.INSUFFICIENT_STOCK, msg, cartId);
  }

  public static AddItemResult insufficientStock(String msg) {
    return new AddItemResult(Status.INSUFFICIENT_STOCK, msg, null);
  }

  public static AddItemResult badRequest(String msg) {
    return new AddItemResult(Status.BAD_REQUEST, msg, null);
  }
}
