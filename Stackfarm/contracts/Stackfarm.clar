;; Yield Farming Token Contract with Multiple Pools and Emergency Withdrawal
(define-fungible-token yield-token)
(define-constant CONTRACT-OWNER tx-sender)

;; Error Codes
(define-constant ERR-TRANSFER-FAILED (err u1))
(define-constant ERR-INSUFFICIENT-BALANCE (err u2))
(define-constant ERR-UNAUTHORIZED (err u403))
(define-constant ERR-INVALID-AMOUNT (err u404))
(define-constant ERR-INVALID-RATE (err u405))
(define-constant ERR-INVALID-POOL (err u406))
(define-constant ERR-INVALID-POOL-ID (err u407))
(define-constant ERR-INVALID-NAME (err u408))

;; Contract Variables
(define-data-var emergency-mode bool false)
(define-data-var emergency-penalty-rate uint u10) ;; 10% penalty
(define-data-var total-allocated-rewards uint u0)
(define-data-var reward-rate uint u10)  ;; 10 tokens per block as base reward
(define-data-var total-staked uint u0)
(define-data-var pool-count uint u0)
(define-constant MAX-REWARD-RATE u1000)

;; Data Structures
(define-map pools 
  { pool-id: uint }
  { name: (string-ascii 32), risk-factor: uint, reward-multiplier: uint, total-staked: uint, active: bool }
)

(define-map user-stakes 
  { user: principal, pool-id: uint }
  { amount: uint, last-update-block: uint }
)

;; Helper functions for validation
(define-private (is-valid-pool-id (pool-id uint))
  (< pool-id (var-get pool-count))
)

(define-private (is-valid-name (name (string-ascii 32)))
  (not (is-eq name ""))
)

;; Initialize the yield farming contract
(define-public (initialize-farm)
  (begin
    (try! (ft-mint? yield-token u1000000 CONTRACT-OWNER))
    (var-set total-allocated-rewards u1000000)
    (var-set reward-rate u10)
    (try! (create-pool "Conservative" u1 u80))  ;; 80% of base rewards, low risk
    (try! (create-pool "Balanced" u5 u120))     ;; 120% of base rewards, medium risk
    (try! (create-pool "Aggressive" u9 u200))   ;; 200% of base rewards, high risk
    (ok true)
  )
)

;; Create a new staking pool
(define-public (create-pool (name (string-ascii 32)) (risk-factor uint) (reward-multiplier uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (is-valid-name name) ERR-INVALID-NAME)
    (asserts! (and (>= risk-factor u1) (<= risk-factor u10)) ERR-INVALID-RATE)
    (asserts! (> reward-multiplier u0) ERR-INVALID-RATE)
    (let ((new-pool-id (var-get pool-count)))
      (map-set pools { pool-id: new-pool-id }
        { name: name, risk-factor: risk-factor, reward-multiplier: reward-multiplier, total-staked: u0, active: true })
      (var-set pool-count (+ (var-get pool-count) u1))
      (ok new-pool-id)
    )
  )
)

;; Stake tokens into a specific pool
(define-public (stake-in-pool (pool-id uint) (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-valid-pool-id pool-id) ERR-INVALID-POOL-ID)
    (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-INVALID-POOL)))
      (asserts! (get active pool) ERR-INVALID-POOL)
      (let ((sender tx-sender) (current-block stacks-block-height) (pool-total-staked (get total-staked pool)))
        (try! (ft-transfer? yield-token amount sender (as-contract tx-sender)))
        (map-set pools { pool-id: pool-id } (merge pool { total-staked: (+ pool-total-staked amount) }))
        (var-set total-staked (+ (var-get total-staked) amount))
        (let ((existing-stake (default-to { amount: u0, last-update-block: current-block }
                (map-get? user-stakes { user: sender, pool-id: pool-id }))))
          (if (> (get amount existing-stake) u0)
            (let ((pending-rewards (calculate-pool-rewards sender pool-id existing-stake current-block)))
              (try! (transfer-reward sender pending-rewards)))
            true)
          (map-set user-stakes { user: sender, pool-id: pool-id }
            { amount: (+ (get amount existing-stake) amount), last-update-block: current-block })
          (ok true)
        )
      )
    )
  )
)

;; Unstake tokens from a specific pool and claim rewards
(define-public (unstake-from-pool (pool-id uint) (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-valid-pool-id pool-id) ERR-INVALID-POOL-ID)
    (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-INVALID-POOL)))
      (let ((sender tx-sender)
            (user-stake (unwrap! (map-get? user-stakes { user: sender, pool-id: pool-id }) ERR-INSUFFICIENT-BALANCE))
            (current-block stacks-block-height)
            (pending-rewards (calculate-pool-rewards sender pool-id user-stake current-block)))
        (asserts! (<= amount (get amount user-stake)) ERR-INSUFFICIENT-BALANCE)
        (try! (transfer-reward sender pending-rewards))
        (try! (as-contract (ft-transfer? yield-token amount tx-sender sender)))
        (map-set user-stakes { user: sender, pool-id: pool-id }
          { amount: (- (get amount user-stake) amount), last-update-block: current-block })
        (map-set pools { pool-id: pool-id } (merge pool { total-staked: (- (get total-staked pool) amount) }))
        (var-set total-staked (- (var-get total-staked) amount))
        (ok true)
      )
    )
  )
)

;; Emergency withdrawal function
(define-public (emergency-withdraw (pool-id uint))
  (begin
    (asserts! (var-get emergency-mode) ERR-UNAUTHORIZED)
    (asserts! (is-valid-pool-id pool-id) ERR-INVALID-POOL-ID)
    (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-INVALID-POOL))
          (sender tx-sender)
          (user-stake (unwrap! (map-get? user-stakes { user: sender, pool-id: pool-id }) ERR-INSUFFICIENT-BALANCE))
          (staked-amount (get amount user-stake))
          (penalty-rate (var-get emergency-penalty-rate)))
      (asserts! (> staked-amount u0) ERR-INSUFFICIENT-BALANCE)
      (let ((penalty-amount (/ (* staked-amount penalty-rate) u100))
            (return-amount (- staked-amount penalty-amount)))
        (try! (as-contract (ft-transfer? yield-token return-amount tx-sender sender)))
        (map-delete user-stakes { user: sender, pool-id: pool-id })
        (map-set pools { pool-id: pool-id } (merge pool { total-staked: (- (get total-staked pool) staked-amount) }))
        (var-set total-staked (- (var-get total-staked) staked-amount))
        (ok return-amount)
      )
    )
  )
)

;; Admin functions
(define-public (set-emergency-mode (active bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set emergency-mode active)
    (ok active)
  )
)

(define-public (set-emergency-penalty (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= new-rate u100) ERR-INVALID-RATE)
    (var-set emergency-penalty-rate new-rate)
    (ok new-rate)
  )
)

(define-public (update-reward-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (and (> new-rate u0) (<= new-rate MAX-REWARD-RATE)) ERR-INVALID-RATE)
    (var-set reward-rate new-rate)
    (ok true)
  )
)

(define-public (update-pool (pool-id uint) (name (string-ascii 32)) (risk-factor uint) 
                           (reward-multiplier uint) (active bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (is-valid-pool-id pool-id) ERR-INVALID-POOL-ID)
    (asserts! (is-valid-name name) ERR-INVALID-NAME)
    (asserts! (and (>= risk-factor u1) (<= risk-factor u10)) ERR-INVALID-RATE)
    (asserts! (> reward-multiplier u0) ERR-INVALID-RATE)
    (let ((pool (unwrap! (map-get? pools { pool-id: pool-id }) ERR-INVALID-POOL)))
      (map-set pools { pool-id: pool-id }
        { name: name, risk-factor: risk-factor, reward-multiplier: reward-multiplier, 
          total-staked: (get total-staked pool), active: active })
      (ok true)
    )
  )
)

;; Helper functions
(define-private (calculate-pool-rewards (user principal) (pool-id uint)
                                       (user-stake { amount: uint, last-update-block: uint })
                                       (current-block uint))
  (let ((blocks-elapsed (- current-block (get last-update-block user-stake)))
        (reward-per-block (var-get reward-rate))
        (pool (unwrap! (map-get? pools { pool-id: pool-id }) u0))
        (pool-multiplier (get reward-multiplier pool))
        (pool-total-staked (get total-staked pool)))
    (if (> pool-total-staked u0)
      (/ (* (get amount user-stake) blocks-elapsed reward-per-block pool-multiplier) 
         (* pool-total-staked u100))
      u0)
  )
)

(define-private (transfer-reward (sender principal) (reward-amount uint))
  (begin
    (try! (ft-mint? yield-token reward-amount sender))
    (ok true)
  )
)

;; Backward compatibility functions
(define-public (stake (amount uint)) 
  (stake-in-pool u0 amount)
)

(define-public (unstake (amount uint)) 
  (unstake-from-pool u0 amount)
)

;; Read-only functions
(define-read-only (get-user-pool-stake (user principal) (pool-id uint))
  (if (is-valid-pool-id pool-id)
    (default-to { amount: u0, last-update-block: u0 }
      (map-get? user-stakes { user: user, pool-id: pool-id }))
    { amount: u0, last-update-block: u0 }
  )
)

(define-read-only (get-user-stake (user principal)) 
  (get-user-pool-stake user u0)
)

(define-read-only (get-pool-info (pool-id uint))
  (if (is-valid-pool-id pool-id)
    (map-get? pools { pool-id: pool-id })
    none
  )
)

(define-read-only (get-pool-count) 
  (var-get pool-count)
)

(define-read-only (get-total-staked) 
  (var-get total-staked)
)

(define-read-only (get-emergency-mode) 
  (var-get emergency-mode)
)

(define-read-only (get-emergency-penalty-rate) 
  (var-get emergency-penalty-rate)
)