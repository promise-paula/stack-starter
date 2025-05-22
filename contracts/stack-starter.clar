;; StackStarter: Decentralized Crowdfunding Protocol
;;
;; A trustless crowdfunding platform built on Stacks Layer 2 that enables 
;; Bitcoin-secured campaign creation, funding, and transparent fund distribution.
;; The protocol includes optional governance mechanisms through contributor voting
;; and ensures campaign creator accountability with built-in milestone funding.

;; Constants

;; Access Control
(define-constant CONTRACT_OWNER tx-sender)

;; Error Codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u101))
(define-constant ERR_CAMPAIGN_ENDED (err u102))
(define-constant ERR_CAMPAIGN_ACTIVE (err u103))
(define-constant ERR_GOAL_NOT_MET (err u104))
(define-constant ERR_ALREADY_REFUNDED (err u105))
(define-constant ERR_NO_CONTRIBUTION (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))
(define-constant ERR_INVALID_PARAMETERS (err u108))
(define-constant ERR_VOTING_PERIOD_ENDED (err u109))
(define-constant ERR_ALREADY_VOTED (err u110))
(define-constant ERR_INSUFFICIENT_VOTING_POWER (err u111))
(define-constant ERR_CONTRIBUTOR_LIST_FULL (err u112))
(define-constant ERR_INVALID_STRING (err u113))

;; Campaign Status Codes
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_SUCCESSFUL u2)
(define-constant STATUS_FAILED u3)
(define-constant STATUS_CANCELLED u4)

;; Validation Constants
(define-constant MAX_DURATION_BLOCKS u144000) ;; ~100 days at 10 min blocks
(define-constant MAX_VOTING_DURATION_BLOCKS u14400) ;; ~10 days
(define-constant MIN_DURATION_BLOCKS u144) ;; ~1 day
(define-constant MAX_CAMPAIGN_ID u1000000) ;; Reasonable upper bound

;; Data Variables

(define-data-var campaign-counter uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% (250/10000)

;; Data Maps

;; Campaign Data Structure
(define-map campaigns
    { campaign-id: uint }
    {
        creator: principal,
        title: (string-ascii 64),
        description: (string-ascii 256),
        goal: uint,
        raised: uint,
        deadline-height: uint,
        created-height: uint,
        status: uint,
        voting-enabled: bool,
        voting-deadline-height: uint,
        votes-for: uint,
        votes-against: uint,
        min-contribution: uint,
    }
)

;; Contribution Tracking
(define-map contributions
    {
        campaign-id: uint,
        contributor: principal,
    }
    {
        amount: uint,
        refunded: bool,
        voting-power: uint,
    }
)

;; Voting Records
(define-map contributor-votes
    {
        campaign-id: uint,
        voter: principal,
    }
    {
        voted: bool,
        vote-for: bool,
    }
)

;; Campaign Contributors List
(define-map campaign-contributors
    { campaign-id: uint }
    { contributor-list: (list 500 principal) }
)

;; Read-only Functions

;; Get campaign details by ID
(define-read-only (get-campaign (campaign-id uint))
    (map-get? campaigns { campaign-id: campaign-id })
)

;; Get contribution details for a specific campaign and contributor
(define-read-only (get-contribution
        (campaign-id uint)
        (contributor principal)
    )
    (map-get? contributions {
        campaign-id: campaign-id,
        contributor: contributor,
    })
)

;; Get total number of campaigns created
(define-read-only (get-campaign-count)
    (var-get campaign-counter)
)

;; Get current platform fee rate
(define-read-only (get-platform-fee-rate)
    (var-get platform-fee-rate)
)

;; Check if a campaign is still active
(define-read-only (is-campaign-active (campaign-id uint))
    (match (get-campaign campaign-id)
        campaign (and
            (is-eq (get status campaign) STATUS_ACTIVE)
            (< stacks-block-height (get deadline-height campaign))
        )
        false
    )
)

;; Check if a campaign has met its funding goal
(define-read-only (is-campaign-successful (campaign-id uint))
    (match (get-campaign campaign-id)
        campaign (>= (get raised campaign) (get goal campaign))
        false
    )
)

;; Calculate platform fee for a given amount
(define-read-only (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Get voter status for a specific campaign
(define-read-only (get-vote-status
        (campaign-id uint)
        (voter principal)
    )
    (map-get? contributor-votes {
        campaign-id: campaign-id,
        voter: voter,
    })
)

;; Private Functions

;; Validate string input to prevent malicious content
(define-private (is-valid-string (input (string-ascii 256)))
    (let ((length (len input)))
        (and
            (> length u0)
            (<= length u256)
            true
        )
    )
)

;; Validate campaign ID is within reasonable bounds
(define-private (is-valid-campaign-id (campaign-id uint))
    (and
        (> campaign-id u0)
        (<= campaign-id MAX_CAMPAIGN_ID)
    )
)

;; Add a contributor to the campaign's contributor list
(define-private (add-contributor-to-list
        (campaign-id uint)
        (contributor principal)
    )
    (let ((current-list (default-to (list)
            (get contributor-list
                (map-get? campaign-contributors { campaign-id: campaign-id })
            ))))
        (if (< (len current-list) u500)
            (begin
                (map-set campaign-contributors { campaign-id: campaign-id } { contributor-list: (unwrap! (as-max-len? (append current-list contributor) u500)
                    ERR_CONTRIBUTOR_LIST_FULL
                ) }
                )
                (ok true)
            )
            (ok true)
        )
    )
)

;; Update campaign status based on current blockchain height
(define-private (update-campaign-status (campaign-id uint))
    (match (get-campaign campaign-id)
        campaign (begin
            (if (>= stacks-block-height (get deadline-height campaign))
                (if (>= (get raised campaign) (get goal campaign))
                    (map-set campaigns { campaign-id: campaign-id }
                        (merge campaign { status: STATUS_SUCCESSFUL })
                    )
                    (map-set campaigns { campaign-id: campaign-id }
                        (merge campaign { status: STATUS_FAILED })
                    )
                )
                true
            )
            true
        )
        false
    )
)