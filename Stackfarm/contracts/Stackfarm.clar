;; Yield Farming Token Contract
(define-fungible-token yield-token)

;; Define contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Error Codes
(define-constant ERR-TRANSFER-FAILED (err u1))
(define-constant ERR-INSUFFICIENT-BALANCE (err u2))
(define-constant ERR-UNAUTHORIZED (err u403))
(define-constant ERR-INVALID-AMOUNT (err u404))
(define-constant ERR-INVALID-RATE (err u405))

;; Farm Pool Contract
(define-data-var total-allocated-rewards uint u0)
(define-data-var reward-rate uint u10)  ;; 10 tokens per block as base reward
(define-data-var total-staked uint u0)
(define-constant MAX-REWARD-RATE u1000)  ;; Define a maximum reward rate

;; Staking Mapping
(define-map user-stakes 
  { user: principal }
  { amount: uint, last-update-block: uint }
)

;; Initialize the yield farming contract
(define-public (initialize-farm)
  (begin
    (try! (ft-mint? yield-token u1000000 CONTRACT-OWNER))
    (var-set total-allocated-rewards u1000000)  ;; Initial reward pool
    (var-set reward-rate u10)
    (ok true)
  )
)

;; Stake tokens into the farm
(define-public (stake (amount uint))
  (begin
    ;; Validate amount
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (let (
      (sender tx-sender)
      (current-block stacks-block-height)
    )
      ;; Attempt to transfer tokens
      (try! (ft-transfer? yield-token amount sender (as-contract tx-sender)))
      
      ;; Update total staked amount
      (var-set total-staked (+ (var-get total-staked) amount))
      
      ;; Record user stake
      (map-set user-stakes 
        { user: sender }
        { 
          amount: amount, 
          last-update-block: current-block 
        }
      )
      
      (ok true)
    )
  )
)

;; Unstake tokens and claim rewards
(define-public (unstake (amount uint))
  (begin
    ;; Validate amount
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (let (
      (sender tx-sender)
      (user-stake (unwrap! (map-get? user-stakes { user: sender }) ERR-INSUFFICIENT-BALANCE))
      (current-block stacks-block-height)
      (pending-rewards (calculate-rewards sender user-stake current-block))
    )
      ;; Validate unstake amount
      (asserts! (<= amount (get amount user-stake)) ERR-INSUFFICIENT-BALANCE)
      
      ;; Calculate and transfer rewards
      (try! (transfer-reward sender pending-rewards))
      
      ;; Transfer staked tokens back to user
      (try! 
        (as-contract 
          (ft-transfer? yield-token amount tx-sender sender)
        )
      )
      
      ;; Update user stake
      (map-set user-stakes 
        { user: sender }
        { 
          amount: (- (get amount user-stake) amount), 
          last-update-block: current-block 
        }
      )
      
      ;; Update total staked amount
      (var-set total-staked (- (var-get total-staked) amount))
      
      (ok true)
    )
  )
)

;; Calculate user rewards based on stake and time
(define-private (calculate-rewards 
  (user principal) 
  (user-stake { amount: uint, last-update-block: uint })
  (current-block uint)
)
  (let (
    (blocks-elapsed (- current-block (get last-update-block user-stake)))
    (reward-per-block (var-get reward-rate))
    (total-stake (var-get total-staked))
  )
    ;; Prevent division by zero
    (if (> total-stake u0)
      (/ 
        (* 
          (get amount user-stake) 
          blocks-elapsed 
          reward-per-block
        ) 
        total-stake
      )
      u0
    )
  )
)

;; Transfer calculated rewards
(define-private (transfer-reward (sender principal) (reward-amount uint))
  (begin
    ;; Mint rewards to user
    (try! (ft-mint? yield-token reward-amount sender))
    (ok true)
  )
)

;; Admin function to update reward rate
(define-public (update-reward-rate (new-rate uint))
  (begin
    ;; Verify caller is contract owner
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Validate the new rate is within acceptable bounds
    (asserts! (and (> new-rate u0) (<= new-rate MAX-REWARD-RATE)) ERR-INVALID-RATE)
    
    ;; Update the reward rate
    (var-set reward-rate new-rate)
    (ok true)
  )
)

;; View function to check user's current stake
(define-read-only (get-user-stake (user principal))
  (default-to 
    { amount: u0, last-update-block: u0 }
    (map-get? user-stakes { user: user })
  )
)

;; View function to get current total staked amount
(define-read-only (get-total-staked)
  (var-get total-staked)
)

