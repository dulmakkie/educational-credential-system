;; Educational Credential Registry
;; Blockchain-based system for issuing and verifying educational certificates and diplomas

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u3001))
(define-constant ERR_CREDENTIAL_NOT_FOUND (err u3002))
(define-constant ERR_INSTITUTION_NOT_FOUND (err u3003))
(define-constant ERR_ALREADY_EXISTS (err u3004))
(define-constant ERR_INVALID_PARAMETERS (err u3005))
(define-constant ERR_INSUFFICIENT_PRIVILEGES (err u3006))
(define-constant ERR_CREDENTIAL_REVOKED (err u3007))
(define-constant ERR_INVALID_INSTITUTION (err u3008))
(define-constant ERR_BATCH_LIMIT_EXCEEDED (err u3009))
(define-constant ERR_INVALID_CREDENTIAL_TYPE (err u3010))

;; Platform constants
(define-constant MAX_BATCH_SIZE u50)
(define-constant MAX_METADATA_LENGTH u256)
(define-constant MIN_INSTITUTION_NAME_LENGTH u3)
(define-constant MAX_INSTITUTION_NAME_LENGTH u64)

;; Institution authorization levels
(define-constant AUTH_LEVEL_BASIC u1)    ;; Basic certificates
(define-constant AUTH_LEVEL_STANDARD u2) ;; Standard academic credentials
(define-constant AUTH_LEVEL_PREMIUM u3)  ;; Advanced degrees and certifications
(define-constant AUTH_LEVEL_ELITE u4)    ;; Research institutions and universities

;; Credential types
(define-constant CRED_TYPE_CERTIFICATE u1)
(define-constant CRED_TYPE_DIPLOMA u2)
(define-constant CRED_TYPE_DEGREE u3)
(define-constant CRED_TYPE_PROFESSIONAL u4)
(define-constant CRED_TYPE_MICRO u5)

;; Credential status
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_REVOKED u2)
(define-constant STATUS_SUSPENDED u3)
(define-constant STATUS_EXPIRED u4)

;; Data Variables
(define-data-var credential-counter uint u0)
(define-data-var institution-counter uint u0)
(define-data-var total-credentials-issued uint u0)
(define-data-var total-verifications uint u0)
(define-data-var system-paused bool false)

;; Institution data structure
(define-map institutions
  { institution-id: uint }
  {
    name: (string-ascii 64),
    issuer: principal,
    authorization-level: uint,
    credentials-issued: uint,
    reputation-score: uint,
    registered-at: uint,
    status: uint,
    contact-info: (string-ascii 128)
  }
)

;; Credential data structure
(define-map credentials
  { credential-id: uint }
  {
    student: principal,
    institution-id: uint,
    credential-type: uint,
    credential-hash: (buff 32),
    metadata-uri: (string-ascii 256),
    issue-date: uint,
    expiry-date: (optional uint),
    status: uint,
    verification-count: uint,
    grade-points: (optional uint)
  }
)

;; Student credentials tracking
(define-map student-portfolios
  { student: principal }
  { credential-ids: (list 100 uint), total-credentials: uint }
)

;; Institution authorization mapping
(define-map institution-authorities
  { institution-id: uint, authority: principal }
  { authorized: bool, role: (string-ascii 32) }
)

;; Verification logs
(define-map verification-logs
  { credential-id: uint, verifier: principal, timestamp: uint }
  { verification-result: bool, purpose: (string-ascii 64) }
)

;; Credential metadata
(define-map credential-metadata
  { credential-id: uint }
  {
    course-name: (string-ascii 128),
    field-of-study: (string-ascii 64),
    honors: (optional (string-ascii 32)),
    skills: (list 10 (string-ascii 32)),
    credits: (optional uint)
  }
)

;; Read-only functions

(define-read-only (get-institution (institution-id uint))
  (map-get? institutions { institution-id: institution-id })
)

(define-read-only (get-credential (credential-id uint))
  (map-get? credentials { credential-id: credential-id })
)

(define-read-only (get-credential-metadata (credential-id uint))
  (map-get? credential-metadata { credential-id: credential-id })
)

(define-read-only (get-student-portfolio (student principal))
  (default-to 
    { credential-ids: (list), total-credentials: u0 }
    (map-get? student-portfolios { student: student })
  )
)

(define-read-only (verify-credential (credential-id uint))
  (match (get-credential credential-id)
    credential-data
    (let (
      (institution-data (unwrap! (get-institution (get institution-id credential-data)) (err u0)))
    )
      (ok {
        valid: (is-eq (get status credential-data) STATUS_ACTIVE),
        student: (get student credential-data),
        institution: (get name institution-data),
        issue-date: (get issue-date credential-data),
        credential-type: (get credential-type credential-data),
        verification-count: (get verification-count credential-data)
      })
    )
    (err u0)
  )
)

(define-read-only (check-institution-authority (institution-id uint) (authority principal))
  (default-to
    { authorized: false, role: "" }
    (map-get? institution-authorities { institution-id: institution-id, authority: authority })
  )
)

(define-read-only (get-system-stats)
  {
    total-institutions: (var-get institution-counter),
    total-credentials: (var-get credential-counter),
    total-verifications: (var-get total-verifications),
    system-paused: (var-get system-paused)
  }
)

(define-read-only (validate-credential-hash (credential-id uint) (provided-hash (buff 32)))
  (match (get-credential credential-id)
    credential-data
    (ok (is-eq (get credential-hash credential-data) provided-hash))
    (err u0)
  )
)

;; Public functions

(define-public (register-institution (name (string-ascii 64)) (auth-level uint) (contact-info (string-ascii 128)))
  (let (
    (institution-id (+ (var-get institution-counter) u1))
  )
    (asserts! (not (var-get system-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (>= (len name) MIN_INSTITUTION_NAME_LENGTH) ERR_INVALID_PARAMETERS)
    (asserts! (<= (len name) MAX_INSTITUTION_NAME_LENGTH) ERR_INVALID_PARAMETERS)
    (asserts! (<= auth-level AUTH_LEVEL_ELITE) ERR_INVALID_PARAMETERS)
    (asserts! (>= auth-level AUTH_LEVEL_BASIC) ERR_INVALID_PARAMETERS)
    
    ;; Create institution record
    (map-set institutions
      { institution-id: institution-id }
      {
        name: name,
        issuer: tx-sender,
        authorization-level: auth-level,
        credentials-issued: u0,
        reputation-score: u100, ;; Start with perfect score
        registered-at: burn-block-height,
        status: STATUS_ACTIVE,
        contact-info: contact-info
      }
    )
    
    ;; Set initial authority
    (map-set institution-authorities
      { institution-id: institution-id, authority: tx-sender }
      { authorized: true, role: "admin" }
    )
    
    (var-set institution-counter institution-id)
    (ok institution-id)
  )
)

(define-public (issue-credential 
  (student principal) 
  (institution-id uint) 
  (credential-type uint) 
  (credential-hash (buff 32))
  (metadata-uri (string-ascii 256))
  (expiry-date (optional uint))
  (course-name (string-ascii 128))
  (field-of-study (string-ascii 64)))
  (let (
    (credential-id (+ (var-get credential-counter) u1))
    (institution-data (unwrap! (get-institution institution-id) ERR_INSTITUTION_NOT_FOUND))
    (authority-check (check-institution-authority institution-id tx-sender))
  )
    (asserts! (not (var-get system-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (get authorized authority-check) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status institution-data) STATUS_ACTIVE) ERR_INVALID_INSTITUTION)
    (asserts! (<= credential-type CRED_TYPE_MICRO) ERR_INVALID_CREDENTIAL_TYPE)
    (asserts! (>= credential-type CRED_TYPE_CERTIFICATE) ERR_INVALID_CREDENTIAL_TYPE)
    (asserts! (<= (len metadata-uri) MAX_METADATA_LENGTH) ERR_INVALID_PARAMETERS)
    
    ;; Check authorization level for credential type
    (asserts! 
      (or 
        (and (is-eq credential-type CRED_TYPE_CERTIFICATE) (>= (get authorization-level institution-data) AUTH_LEVEL_BASIC))
        (and (is-eq credential-type CRED_TYPE_DIPLOMA) (>= (get authorization-level institution-data) AUTH_LEVEL_STANDARD))
        (and (is-eq credential-type CRED_TYPE_DEGREE) (>= (get authorization-level institution-data) AUTH_LEVEL_PREMIUM))
        (and (is-eq credential-type CRED_TYPE_PROFESSIONAL) (>= (get authorization-level institution-data) AUTH_LEVEL_STANDARD))
        (and (is-eq credential-type CRED_TYPE_MICRO) (>= (get authorization-level institution-data) AUTH_LEVEL_BASIC))
      )
      ERR_INSUFFICIENT_PRIVILEGES
    )
    
    ;; Create credential record
    (map-set credentials
      { credential-id: credential-id }
      {
        student: student,
        institution-id: institution-id,
        credential-type: credential-type,
        credential-hash: credential-hash,
        metadata-uri: metadata-uri,
        issue-date: burn-block-height,
        expiry-date: expiry-date,
        status: STATUS_ACTIVE,
        verification-count: u0,
        grade-points: none
      }
    )
    
    ;; Add metadata
    (map-set credential-metadata
      { credential-id: credential-id }
      {
        course-name: course-name,
        field-of-study: field-of-study,
        honors: none,
        skills: (list),
        credits: none
      }
    )
    
    ;; Update student portfolio
    (let (
      (current-portfolio (get-student-portfolio student))
    )
      (map-set student-portfolios
        { student: student }
        {
          credential-ids: (unwrap! (as-max-len? (append (get credential-ids current-portfolio) credential-id) u100) ERR_INVALID_PARAMETERS),
          total-credentials: (+ (get total-credentials current-portfolio) u1)
        }
      )
    )
    
    ;; Update institution stats
    (map-set institutions
      { institution-id: institution-id }
      (merge institution-data {
        credentials-issued: (+ (get credentials-issued institution-data) u1)
      })
    )
    
    ;; Update global counters
    (var-set credential-counter credential-id)
    (var-set total-credentials-issued (+ (var-get total-credentials-issued) u1))
    
    (ok credential-id)
  )
)

(define-public (verify-credential-by-verifier (credential-id uint) (purpose (string-ascii 64)))
  (let (
    (credential-data (unwrap! (get-credential credential-id) ERR_CREDENTIAL_NOT_FOUND))
    (verification-result (is-eq (get status credential-data) STATUS_ACTIVE))
  )
    (asserts! (not (var-get system-paused)) ERR_NOT_AUTHORIZED)
    
    ;; Log verification
    (map-set verification-logs
      { credential-id: credential-id, verifier: tx-sender, timestamp: burn-block-height }
      { verification-result: verification-result, purpose: purpose }
    )
    
    ;; Update verification count
    (map-set credentials
      { credential-id: credential-id }
      (merge credential-data {
        verification-count: (+ (get verification-count credential-data) u1)
      })
    )
    
    ;; Update global verification counter
    (var-set total-verifications (+ (var-get total-verifications) u1))
    
    (ok verification-result)
  )
)

(define-public (revoke-credential (credential-id uint))
  (let (
    (credential-data (unwrap! (get-credential credential-id) ERR_CREDENTIAL_NOT_FOUND))
    (authority-check (check-institution-authority (get institution-id credential-data) tx-sender))
  )
    (asserts! (not (var-get system-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (get authorized authority-check) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq (get status credential-data) STATUS_REVOKED)) ERR_CREDENTIAL_REVOKED)
    
    ;; Update credential status
    (map-set credentials
      { credential-id: credential-id }
      (merge credential-data { status: STATUS_REVOKED })
    )
    
    (ok credential-id)
  )
)

(define-public (add-institution-authority (institution-id uint) (authority principal) (role (string-ascii 32)))
  (let (
    (institution-data (unwrap! (get-institution institution-id) ERR_INSTITUTION_NOT_FOUND))
    (current-authority (check-institution-authority institution-id tx-sender))
  )
    (asserts! (not (var-get system-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (get authorized current-authority) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get issuer institution-data) tx-sender) ERR_NOT_AUTHORIZED)
    
    (map-set institution-authorities
      { institution-id: institution-id, authority: authority }
      { authorized: true, role: role }
    )
    
    (ok authority)
  )
)

(define-public (batch-issue-credentials (credentials-data (list 10 { student: principal, credential-type: uint, credential-hash: (buff 32), metadata-uri: (string-ascii 256) })) (institution-id uint))
  (let (
    (institution-data (unwrap! (get-institution institution-id) ERR_INSTITUTION_NOT_FOUND))
    (authority-check (check-institution-authority institution-id tx-sender))
  )
    (asserts! (not (var-get system-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (get authorized authority-check) ERR_NOT_AUTHORIZED)
    (asserts! (<= (len credentials-data) MAX_BATCH_SIZE) ERR_BATCH_LIMIT_EXCEEDED)
    
    ;; Process batch (simplified - in production would iterate through list)
    (var-set total-credentials-issued (+ (var-get total-credentials-issued) (len credentials-data)))
    
    (ok (len credentials-data))
  )
)

(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set system-paused true)
    (ok true)
  )
)

(define-public (resume-system)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set system-paused false)
    (ok true)
  )
)

(define-public (update-institution-status (institution-id uint) (new-status uint))
  (let (
    (institution-data (unwrap! (get-institution institution-id) ERR_INSTITUTION_NOT_FOUND))
  )
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) (is-eq tx-sender (get issuer institution-data))) ERR_NOT_AUTHORIZED)
    (asserts! (<= new-status STATUS_EXPIRED) ERR_INVALID_PARAMETERS)
    
    (map-set institutions
      { institution-id: institution-id }
      (merge institution-data { status: new-status })
    )
    
    (ok institution-id)
  )
)

;; title: credential-registry
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

