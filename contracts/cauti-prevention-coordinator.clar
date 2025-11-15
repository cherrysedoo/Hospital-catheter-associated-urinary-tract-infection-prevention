;; CAUTI Prevention Coordinator Smart Contract
;; Manages catheter-associated urinary tract infection prevention

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-input (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-already-removed (err u105))
(define-constant err-invalid-status (err u106))

;; Data Variables
(define-data-var catheter-id-nonce uint u0)
(define-data-var assessment-id-nonce uint u0)
(define-data-var cauti-event-id-nonce uint u0)
(define-data-var total-catheter-days uint u0)
(define-data-var total-cauti-events uint u0)

;; Data Maps
(define-map catheters
  { catheter-id: uint }
  {
    patient-id: (string-ascii 64),
    insertion-date: uint,
    indication: (string-ascii 256),
    bundle-complete: bool,
    inserted-by: principal,
    removal-date: (optional uint),
    is-active: bool,
    unit-id: (string-ascii 64),
    catheter-size: uint
  }
)

(define-map necessity-assessments
  { assessment-id: uint }
  {
    catheter-id: uint,
    assessment-date: uint,
    is-necessary: bool,
    justification: (string-ascii 512),
    assessed-by: principal,
    next-review-date: uint
  }
)

(define-map catheter-removals
  { catheter-id: uint }
  {
    removal-date: uint,
    removal-reason: (string-ascii 256),
    removed-by: principal,
    post-removal-outcome: (string-ascii 256),
    complications: bool
  }
)

(define-map cauti-events
  { event-id: uint }
  {
    catheter-id: uint,
    patient-id: (string-ascii 64),
    event-date: uint,
    diagnosis-details: (string-ascii 512),
    reported-by: principal,
    catheter-days-before-infection: uint,
    severity-level: uint
  }
)

(define-map bundle-compliance
  { catheter-id: uint }
  {
    hand-hygiene: bool,
    aseptic-technique: bool,
    appropriate-size: bool,
    securement-done: bool,
    closed-drainage: bool,
    compliance-score: uint
  }
)

(define-map staff-training
  { staff-principal: principal }
  {
    last-training-date: uint,
    competency-verified: bool,
    training-hours: uint,
    certifications: (list 10 (string-ascii 128))
  }
)

(define-map authorized-staff
  { staff-principal: principal }
  {
    role: (string-ascii 64),
    authorized: bool,
    authorization-date: uint
  }
)

;; Private Functions
(define-private (calculate-bundle-score (hand bool) (aseptic bool) (size bool) (secure bool) (closed bool))
  (let
    (
      (score (+ 
        (if hand u20 u0)
        (if aseptic u20 u0)
        (if size u20 u0)
        (if secure u20 u0)
        (if closed u20 u0)
      ))
    )
    score
  )
)

(define-private (is-authorized (staff principal))
  (match (map-get? authorized-staff { staff-principal: staff })
    auth-data (get authorized auth-data)
    false
  )
)

(define-private (calculate-catheter-days (insertion-date uint) (removal-date uint))
  (let
    (
      (days (/ (- removal-date insertion-date) u86400))
    )
    days
  )
)

;; Public Functions

;; Register new catheter insertion
(define-public (register-catheter-insertion 
    (patient-id (string-ascii 64))
    (indication (string-ascii 256))
    (bundle-complete bool)
    (unit-id (string-ascii 64))
    (catheter-size uint))
  (let
    (
      (new-catheter-id (+ (var-get catheter-id-nonce) u1))
      (current-time block-height)
    )
    (asserts! (is-authorized tx-sender) err-unauthorized)
    (asserts! (> (len patient-id) u0) err-invalid-input)
    (asserts! (> (len indication) u0) err-invalid-input)
    
    (map-set catheters
      { catheter-id: new-catheter-id }
      {
        patient-id: patient-id,
        insertion-date: current-time,
        indication: indication,
        bundle-complete: bundle-complete,
        inserted-by: tx-sender,
        removal-date: none,
        is-active: true,
        unit-id: unit-id,
        catheter-size: catheter-size
      }
    )
    
    (var-set catheter-id-nonce new-catheter-id)
    (ok new-catheter-id)
  )
)

;; Perform daily necessity assessment
(define-public (perform-necessity-assessment
    (catheter-id uint)
    (is-necessary bool)
    (justification (string-ascii 512))
    (next-review-days uint))
  (let
    (
      (new-assessment-id (+ (var-get assessment-id-nonce) u1))
      (current-time block-height)
      (catheter-data (unwrap! (map-get? catheters { catheter-id: catheter-id }) err-not-found))
    )
    (asserts! (is-authorized tx-sender) err-unauthorized)
    (asserts! (get is-active catheter-data) err-already-removed)
    (asserts! (> (len justification) u0) err-invalid-input)
    
    (map-set necessity-assessments
      { assessment-id: new-assessment-id }
      {
        catheter-id: catheter-id,
        assessment-date: current-time,
        is-necessary: is-necessary,
        justification: justification,
        assessed-by: tx-sender,
        next-review-date: (+ current-time (* next-review-days u144))
      }
    )
    
    (var-set assessment-id-nonce new-assessment-id)
    (ok new-assessment-id)
  )
)

;; Coordinate catheter removal
(define-public (coordinate-catheter-removal
    (catheter-id uint)
    (removal-reason (string-ascii 256))
    (post-removal-outcome (string-ascii 256))
    (complications bool))
  (let
    (
      (current-time block-height)
      (catheter-data (unwrap! (map-get? catheters { catheter-id: catheter-id }) err-not-found))
      (days-inserted (calculate-catheter-days (get insertion-date catheter-data) current-time))
    )
    (asserts! (is-authorized tx-sender) err-unauthorized)
    (asserts! (get is-active catheter-data) err-already-removed)
    (asserts! (> (len removal-reason) u0) err-invalid-input)
    
    ;; Update catheter record
    (map-set catheters
      { catheter-id: catheter-id }
      (merge catheter-data {
        removal-date: (some current-time),
        is-active: false
      })
    )
    
    ;; Record removal details
    (map-set catheter-removals
      { catheter-id: catheter-id }
      {
        removal-date: current-time,
        removal-reason: removal-reason,
        removed-by: tx-sender,
        post-removal-outcome: post-removal-outcome,
        complications: complications
      }
    )
    
    ;; Update total catheter days
    (var-set total-catheter-days (+ (var-get total-catheter-days) days-inserted))
    
    (ok true)
  )
)

;; Report CAUTI event
(define-public (report-cauti-event
    (catheter-id uint)
    (diagnosis-details (string-ascii 512))
    (severity-level uint))
  (let
    (
      (new-event-id (+ (var-get cauti-event-id-nonce) u1))
      (current-time block-height)
      (catheter-data (unwrap! (map-get? catheters { catheter-id: catheter-id }) err-not-found))
      (days-before-infection (calculate-catheter-days (get insertion-date catheter-data) current-time))
    )
    (asserts! (is-authorized tx-sender) err-unauthorized)
    (asserts! (> (len diagnosis-details) u0) err-invalid-input)
    (asserts! (<= severity-level u5) err-invalid-input)
    
    (map-set cauti-events
      { event-id: new-event-id }
      {
        catheter-id: catheter-id,
        patient-id: (get patient-id catheter-data),
        event-date: current-time,
        diagnosis-details: diagnosis-details,
        reported-by: tx-sender,
        catheter-days-before-infection: days-before-infection,
        severity-level: severity-level
      }
    )
    
    (var-set cauti-event-id-nonce new-event-id)
    (var-set total-cauti-events (+ (var-get total-cauti-events) u1))
    
    (ok new-event-id)
  )
)

;; Track bundle compliance
(define-public (track-bundle-compliance
    (catheter-id uint)
    (hand-hygiene bool)
    (aseptic-technique bool)
    (appropriate-size bool)
    (securement-done bool)
    (closed-drainage bool))
  (let
    (
      (catheter-data (unwrap! (map-get? catheters { catheter-id: catheter-id }) err-not-found))
      (compliance-score (calculate-bundle-score hand-hygiene aseptic-technique appropriate-size securement-done closed-drainage))
    )
    (asserts! (is-authorized tx-sender) err-unauthorized)
    
    (map-set bundle-compliance
      { catheter-id: catheter-id }
      {
        hand-hygiene: hand-hygiene,
        aseptic-technique: aseptic-technique,
        appropriate-size: appropriate-size,
        securement-done: securement-done,
        closed-drainage: closed-drainage,
        compliance-score: compliance-score
      }
    )
    
    (ok compliance-score)
  )
)

;; Update staff training
(define-public (update-staff-training
    (staff-member principal)
    (competency-verified bool)
    (training-hours uint))
  (let
    (
      (current-time block-height)
    )
    (asserts! (or (is-eq tx-sender contract-owner) (is-eq tx-sender staff-member)) err-unauthorized)
    
    (map-set staff-training
      { staff-principal: staff-member }
      {
        last-training-date: current-time,
        competency-verified: competency-verified,
        training-hours: training-hours,
        certifications: (list)
      }
    )
    
    (ok true)
  )
)

;; Authorize staff member
(define-public (authorize-staff
    (staff-member principal)
    (role (string-ascii 64)))
  (let
    (
      (current-time block-height)
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set authorized-staff
      { staff-principal: staff-member }
      {
        role: role,
        authorized: true,
        authorization-date: current-time
      }
    )
    
    (ok true)
  )
)

;; Revoke staff authorization
(define-public (revoke-staff-authorization (staff-member principal))
  (let
    (
      (auth-data (unwrap! (map-get? authorized-staff { staff-principal: staff-member }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set authorized-staff
      { staff-principal: staff-member }
      (merge auth-data { authorized: false })
    )
    
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-catheter-details (catheter-id uint))
  (ok (map-get? catheters { catheter-id: catheter-id }))
)

(define-read-only (get-assessment-details (assessment-id uint))
  (ok (map-get? necessity-assessments { assessment-id: assessment-id }))
)

(define-read-only (get-removal-details (catheter-id uint))
  (ok (map-get? catheter-removals { catheter-id: catheter-id }))
)

(define-read-only (get-cauti-event-details (event-id uint))
  (ok (map-get? cauti-events { event-id: event-id }))
)

(define-read-only (get-bundle-compliance (catheter-id uint))
  (ok (map-get? bundle-compliance { catheter-id: catheter-id }))
)

(define-read-only (get-staff-training (staff-member principal))
  (ok (map-get? staff-training { staff-principal: staff-member }))
)

(define-read-only (check-staff-authorization (staff-member principal))
  (ok (map-get? authorized-staff { staff-principal: staff-member }))
)

(define-read-only (get-cauti-rate)
  (let
    (
      (total-days (var-get total-catheter-days))
      (total-events (var-get total-cauti-events))
    )
    (if (> total-days u0)
      (ok (/ (* total-events u1000) total-days))
      (ok u0)
    )
  )
)

(define-read-only (get-total-statistics)
  (ok {
    total-catheter-days: (var-get total-catheter-days),
    total-cauti-events: (var-get total-cauti-events),
    total-catheters: (var-get catheter-id-nonce),
    total-assessments: (var-get assessment-id-nonce)
  })
)

(define-read-only (check-catheter-necessity (catheter-id uint))
  (let
    (
      (catheter-data (unwrap! (map-get? catheters { catheter-id: catheter-id }) err-not-found))
    )
    (ok (get is-active catheter-data))
  )
)


;; title: cauti-prevention-coordinator
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

