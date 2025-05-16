;; SATOSHI STANDARD: Bitcoin-Backed Stablecoin Protocol for Stacks
;; 
;; A decentralized, overcollateralized stablecoin protocol built on Stacks,
;; leveraging Bitcoin as collateral to mint USD-pegged stablecoins.
;; 
;; The protocol allows users to lock Bitcoin as collateral in vaults and mint
;; STUSD (Satoshi Standard USD) stablecoins against their collateral. It
;; implements risk management with liquidations for undercollateralized
;; positions and oracle price feeds to maintain proper collateral ratios.
;;
;; Compatible with Stacks Layer 2 and optimized for Bitcoin finality.

;; Trait Definitions

(define-trait sip-010-token
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 5) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
  )
)

;; Error Codes

(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1001))
(define-constant ERR-INVALID-COLLATERAL (err u1002))
(define-constant ERR-UNDERCOLLATERALIZED (err u1003))
(define-constant ERR-ORACLE-PRICE-UNAVAILABLE (err u1004))
(define-constant ERR-LIQUIDATION-FAILED (err u1005))
(define-constant ERR-MINT-LIMIT-EXCEEDED (err u1006))
(define-constant ERR-INVALID-PARAMETERS (err u1007))
(define-constant ERR-UNAUTHORIZED-VAULT-ACTION (err u1008))

;; Security Constants

(define-constant MAX-BTC-PRICE u1000000000000)  ;; Maximum reasonable BTC price
(define-constant MAX-TIMESTAMP u18446744073709551615)  ;; Maximum uint timestamp
(define-constant CONTRACT-OWNER tx-sender)

;; Protocol Configuration

(define-data-var stablecoin-name (string-ascii 32) "Satoshi Standard USD")
(define-data-var stablecoin-symbol (string-ascii 5) "STUSD")
(define-data-var total-supply uint u0)
(define-data-var collateralization-ratio uint u150)  ;; 150% collateralization required
(define-data-var liquidation-threshold uint u125)    ;; Liquidate at 125% collateralization

;; Protocol Parameters

(define-data-var mint-fee-bps uint u50)         ;; 0.5% fee on minting
(define-data-var redemption-fee-bps uint u50)   ;; 0.5% fee on redemption
(define-data-var max-mint-limit uint u1000000)  ;; Maximum STUSD that can be minted

;; Oracle System

;; Map of authorized oracle providers
(define-map btc-price-oracles principal bool)

;; Latest BTC price data
(define-map last-btc-price 
  {
    timestamp: uint,
    price: uint
  }
  uint
)

;; Vault System

;; Vault data structure storing collateral and debt information
(define-map vaults 
  {
    owner: principal, 
    id: uint
  }
  {
    collateral-amount: uint,
    stablecoin-minted: uint,
    created-at: uint
  }
)

;; Counter for tracking vault IDs
(define-data-var vault-counter uint u0)

;; Oracle Management Functions

;; Add a new BTC price oracle provider
(define-public (add-btc-price-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and 
      (not (is-eq oracle CONTRACT-OWNER)) 
      (not (is-eq oracle tx-sender))
    ) ERR-INVALID-PARAMETERS)
    (map-set btc-price-oracles oracle true)
    (ok true)
  )
)

;; Update the BTC price from an authorized oracle
(define-public (update-btc-price (price uint) (timestamp uint))
  (begin
    (asserts! (is-some (map-get? btc-price-oracles tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (and 
      (> price u0)
      (<= price MAX-BTC-PRICE)
    ) ERR-INVALID-PARAMETERS)
    (asserts! (<= timestamp MAX-TIMESTAMP) ERR-INVALID-PARAMETERS)
    (map-set last-btc-price 
      {
        timestamp: timestamp, 
        price: price
      }
      price
    )
    (ok true)
  )
)

;; Vault Management Functions

;; Create a new vault with Bitcoin collateral
(define-public (create-vault (collateral-amount uint))
  (let 
    (
      (vault-id (+ (var-get vault-counter) u1))
      (new-vault 
        {
          owner: tx-sender,
          id: vault-id
        }
      )
    )
    (asserts! (> collateral-amount u0) ERR-INVALID-COLLATERAL)
    (asserts! (< vault-id (+ (var-get vault-counter) u1000)) ERR-INVALID-PARAMETERS)
    (var-set vault-counter vault-id)
    (map-set vaults new-vault 
      {
        collateral-amount: collateral-amount,
        stablecoin-minted: u0,
        created-at: stacks-block-height
      }
    )
    (ok vault-id)
  )
)