//
//  PurchasesAPI.swift
//  channel
//
//  Created by Michael Kalygin on 21/04/16.
//  Copyright © 2016 caffeinelabs. All rights reserved.
//

import Foundation
import StoreKit
import JavaScriptCore

@objc protocol PurchasesAPIExport: JSExport {
  static func instance() -> PurchasesAPIExport
  @objc(purchaseProduct::) func purchaseProduct(productId: String, jsCallback: JSValue?)
  @objc(isProductPurchased:) func isProductPurchased(productId: String) -> Bool
  @objc(getLocalizedPrices::) func getLocalizedPrices(productIds: [String], jsCallback: JSValue?)
}

@objc class PurchasesAPI: NSObject, PurchasesAPIExport {
  var request: SKProductsRequest?
  var completion: (([SKProduct]?, NSError?) -> Void)?
  
  // function (response, error) { ... }
  var jsCallback: JSValue?
  
  static func instance() -> PurchasesAPIExport {
    return PurchasesAPI()
  }
  
  override init() {
    super.init()
    SKPaymentQueue.defaultQueue().addTransactionObserver(self)
  }
  
  /*
  / Public API.
  */
  
  @objc(purchaseProduct::) func purchaseProduct(productId: String, jsCallback: JSValue?) {
    print("Purchasing product with ID \(productId)...")
    
    self.getProducts([productId], completion: { products, error in
      guard let product = products?.first else {
        print("Purchase error: \(error)")
        self.resetRequest(errorMessage: error?.localizedDescription)
        return
      }
      
      self.queuePayment(product)
    }, jsCallback: jsCallback)
  }
  
  @objc(isProductPurchased:) func isProductPurchased(productId: String) -> Bool {
    return NSUserDefaults.standardUserDefaults().boolForKey(productId)
  }
  
  @objc(getLocalizedPrices::) func getLocalizedPrices(productIds: [String], jsCallback: JSValue?) {
    self.getProducts(productIds, completion: { products, error in
      if (products == nil) {
        print("Purchase error: \(error)")
        self.resetRequest(errorMessage: error?.localizedDescription)
        return
      }
      
      var prices = [String: String]()
      for product in products! {
        prices[product.productIdentifier] = product.localizedPrice()
      }

      self.resetRequest(prices)
    }, jsCallback: jsCallback)
  }
  
  /*
   / Private helper methods.
   */
  
  private func getProducts(productIds: [String], completion: ([SKProduct]?, NSError?) -> Void, jsCallback: JSValue?) {
    guard self.request == nil else { return }
    
    print("Getting products information with IDs \(productIds)...")
    
    self.completion = completion
    self.jsCallback = jsCallback
    self.request = SKProductsRequest(productIdentifiers: Set(productIds))
    self.request?.delegate = self
    self.request?.start()
  }
  
  private func queuePayment(product: SKProduct) {
    print("Queueing a payment transaction for product \(product)...")
    
    let payment = SKPayment(product: product)
    SKPaymentQueue.defaultQueue().addPayment(payment)
  }
  
  private func onProductPurchaseSuccess(productId: String) {
    print("Purchase of product with ID \(productId) was successful!")
    
    NSUserDefaults.standardUserDefaults().setBool(true, forKey: productId)
    
    self.resetRequest(productId)
  }
  
  private func onProductPurchaseFailure(errorMessage: String? = nil) {
    print("Purchase failed!")
    
    self.resetRequest(errorMessage: errorMessage)
  }
  
  private func resetRequest(result: AnyObject = NSNull(), errorMessage: String? = nil) {
    self.callJsCallback(result, errorMessage: errorMessage)
    
    self.request = nil
    self.completion = nil
    self.jsCallback = nil
  }
  
  private func callJsCallback(result: AnyObject = NSNull(), errorMessage: String? = nil) {
    let error = errorMessage != nil ? ["message": errorMessage] as! AnyObject : NSNull()
    self.jsCallback?.callWithArguments([result, error])
  }
}

extension PurchasesAPI: SKProductsRequestDelegate {
  // Called when the Apple App Store responds to the product request.
  func productsRequest(request: SKProductsRequest, didReceiveResponse response: SKProductsResponse) {
    let products = response.products
    let invalidProductIds = response.invalidProductIdentifiers
    
    if (invalidProductIds.count > 0) {
      print("Purchase error: invalid product identifiers \(invalidProductIds)")
    }
    
    self.completion?(products, nil)
  }
  
  // Called if the request failed to execute.
  func request(request: SKRequest, didFailWithError error: NSError) {
    self.completion?(nil, error)
  }
  
  // Called when the request has completed.
  func requestDidFinish(request: SKRequest) {
  }
}

extension PurchasesAPI: SKPaymentTransactionObserver {
  // Tells an observer that one or more transactions have been updated.
  func paymentQueue(queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
    for transaction in transactions {
      switch transaction.transactionState {
      case .Purchasing:
        break;
      case .Purchased:
        self.completeTransaction(transaction)
      case .Failed:
        self.failTransaction(transaction)
      case .Restored:
        self.restoreTransaction(transaction)
      case .Deferred:
        break;
      }
    }
  }
  
  private func completeTransaction(transaction: SKPaymentTransaction) {
    SKPaymentQueue.defaultQueue().finishTransaction(transaction)
    
    let productId = transaction.payment.productIdentifier
    self.onProductPurchaseSuccess(productId)
  }
  
  private func failTransaction(transaction: SKPaymentTransaction) {
    SKPaymentQueue.defaultQueue().finishTransaction(transaction)
    
    if transaction.error!.code != SKErrorCode.PaymentCancelled.rawValue {
      let errorMessage = "Purchase error: (transaction \(transaction.transactionIdentifier)) \(transaction.error!.description)"
      print(errorMessage)
      self.onProductPurchaseFailure(errorMessage)
    }
  }
  
  private func restoreTransaction(transaction: SKPaymentTransaction) {
    SKPaymentQueue.defaultQueue().finishTransaction(transaction)
    
    guard let original = transaction.originalTransaction else {
      let errorMessage = "Purchase error: unable to restore transaction \(transaction.transactionIdentifier)"
      print(errorMessage)
      self.onProductPurchaseFailure(errorMessage)
      return
    }
    
    let productId = original.payment.productIdentifier
    self.onProductPurchaseSuccess(productId)
  }
}