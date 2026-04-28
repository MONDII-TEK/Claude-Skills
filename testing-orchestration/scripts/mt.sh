#!/usr/bin/env bash
# =============================================================================
# mt.sh — Manual Test Executor (middleware)
# =============================================================================
#
# Prepares the full test environment (tokens, Stripe IDs, base URL) and
# executes whatever bash command is passed as argument. Nothing more.
#
# Usage:
#   ./scripts/mt.sh 'curl -sk $BASE_URL/api/health'
#   ./scripts/mt.sh --env          # Show detected environment
#   ./scripts/mt.sh --db "..."     # Run python in backend container (log-filtered)
#   ./scripts/mt.sh --restore      # Restore membership for test user
#   ./scripts/mt.sh --reset-credits
#   ./scripts/mt.sh --refresh      # Force token refresh
#
# All variables are exported and available inside the command:
#   $BASE_URL, $ADMIN_TOKEN, $CLIENT_TOKEN, $STRIPE_KEY,
#   $CUSTOMER_ID, $PM_ID, $STRIPE_PRICE, $TEST_USER_ID, $TEST_PLAN_ID,
#   $FLASK_ENV, $WEBHOOK_WAIT
#
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
TOKEN_CACHE="/tmp/mt_tokens.json"
TOKEN_MAX_AGE=1200  # 20 min (tokens expire at 30)
WEBHOOK_WAIT=4

# ---------------------------------------------------------------------------
# Detect or load environment
# ---------------------------------------------------------------------------

_load_stripe_key() {
    export STRIPE_KEY=$(grep '^STRIPE_TEST_SECRET_KEY=' "$ENV_FILE" | cut -d= -f2-)
    [[ -n "$STRIPE_KEY" ]] || { echo "FATAL: STRIPE_TEST_SECRET_KEY not in .env" >&2; exit 1; }
}

_detect_base_url() {
    if [[ -n "${BASE_URL:-}" ]]; then return; fi
    if curl -sk --max-time 3 "https://example.zentral.art/api/health" &>/dev/null; then
        export BASE_URL="https://example.zentral.art"
    elif curl -sk --max-time 3 "http://localhost:5005/api/health" &>/dev/null; then
        export BASE_URL="http://localhost:5005"
    elif curl -sk --max-time 3 "http://localhost:5001/api/health" &>/dev/null; then
        export BASE_URL="http://localhost:5001"
    else
        echo "FATAL: No backend reachable" >&2; exit 1
    fi
}

_detect_flask_env() {
    export FLASK_ENV=$(docker exec ironvolt-backend printenv FLASK_ENV 2>/dev/null || echo "unknown")
}

# Run python inside backend container, filtering scheduler log noise
_db_query() {
    docker exec ironvolt-backend python3 -c "
from app import create_app
from models import *
app = create_app()
with app.app_context():
    $1
" 2>&1 | grep -v -E '^\[20[0-9]{2}-|^Traceback|^  File |^    |^[A-Za-z]*Error:|^$|LegacyAPIWarning|SAWarning|<string>:[0-9]+:' | grep -v -E 'in logging_config:|task_registered|task_synced|scheduler_loop|scheduler_started|scheduler_stopped|Background scheduler|initialized \|' || true
}

_detect_stripe_ids() {
    if [[ -z "${CUSTOMER_ID:-}" ]]; then
        export CUSTOMER_ID=$(_db_query "u=User.query.get($TEST_USER_ID); print(u.stripe_customer_id or '')" | head -1)
        [[ -n "$CUSTOMER_ID" ]] || { echo "FATAL: User $TEST_USER_ID has no stripe_customer_id" >&2; exit 1; }
    fi

    if [[ -z "${PM_ID:-}" ]]; then
        export PM_ID=$(curl -s "https://api.stripe.com/v1/payment_methods?customer=$CUSTOMER_ID&type=card&limit=1" \
            -u "$STRIPE_KEY:" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'] if d['data'] else '')" 2>/dev/null)
    fi

    if [[ -z "${STRIPE_PRICE:-}" ]]; then
        # Primary: look up the synced Stripe price for TEST_PLAN_ID from PaymentProviderPlan
        export STRIPE_PRICE=$(_db_query "ppp=PaymentProviderPlan.query.filter_by(subscription_plan_id=$TEST_PLAN_ID, provider='stripe').first(); print(ppp.to_dict()['external_price_id'] if ppp else '')" | head -1 || true)
        if [[ -z "$STRIPE_PRICE" || "$STRIPE_PRICE" == "None" ]]; then
            # Fallback: try the plan's stripe_price_id field
            export STRIPE_PRICE=$(_db_query "p=SubscriptionPlan.query.get($TEST_PLAN_ID); print(p.stripe_price_id or '')" | head -1 || true)
        fi
        if [[ -z "$STRIPE_PRICE" || "$STRIPE_PRICE" == "None" ]]; then
            # Last resort: infer from latest Stripe subscription
            export STRIPE_PRICE=$(curl -s "https://api.stripe.com/v1/subscriptions?customer=$CUSTOMER_ID&limit=1&status=all" \
                -u "$STRIPE_KEY:" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['items']['data'][0]['price']['id'] if d['data'] else '')" 2>/dev/null)
        fi
        [[ -n "$STRIPE_PRICE" && "$STRIPE_PRICE" != "None" ]] || { echo "FATAL: Cannot detect Stripe price. Export STRIPE_PRICE=price_XXX" >&2; exit 1; }
    fi
}

# ---------------------------------------------------------------------------
# Token management (cached to disk, refreshed when stale)
# ---------------------------------------------------------------------------

_login() {
    curl -sk "${BASE_URL}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"email\":\"$1\",\"password\":\"$2\"}" 2>/dev/null
}

_refresh_tokens() {
    local admin_resp client_resp
    admin_resp=$(_login "${MT_ADMIN_EMAIL:-superadmin@example.com}" "${MT_ADMIN_PASS:-super123}")
    client_resp=$(_login "${MT_CLIENT_EMAIL:-superadmin@example.com}" "${MT_CLIENT_PASS:-super123}")

    export ADMIN_TOKEN=$(echo "$admin_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)
    export CLIENT_TOKEN=$(echo "$client_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)

    [[ -n "$ADMIN_TOKEN" ]] || { echo "FATAL: Admin login failed" >&2; exit 1; }
    [[ -n "$CLIENT_TOKEN" ]] || { echo "FATAL: Client login failed" >&2; exit 1; }

    echo "{\"admin\":\"$ADMIN_TOKEN\",\"client\":\"$CLIENT_TOKEN\",\"ts\":$(date +%s)}" > "$TOKEN_CACHE"
    echo "Tokens refreshed" >&2
}

_ensure_tokens() {
    if [[ -f "$TOKEN_CACHE" ]]; then
        local ts now
        ts=$(python3 -c "import json; print(json.load(open('$TOKEN_CACHE'))['ts'])" 2>/dev/null || echo 0)
        now=$(date +%s)
        if (( now - ts < TOKEN_MAX_AGE )); then
            export ADMIN_TOKEN=$(python3 -c "import json; print(json.load(open('$TOKEN_CACHE'))['admin'])" 2>/dev/null)
            export CLIENT_TOKEN=$(python3 -c "import json; print(json.load(open('$TOKEN_CACHE'))['client'])" 2>/dev/null)
            return
        fi
    fi
    _refresh_tokens
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

export TEST_USER_ID="${TEST_USER_ID:-1}"
export TEST_PLAN_ID="${TEST_PLAN_ID:-1}"
# Auto-detect credits from DB if not overridden
if [[ -z "${TEST_PLAN_CREDITS:-}" ]]; then
    export TEST_PLAN_CREDITS=$(_db_query "p=SubscriptionPlan.query.get($TEST_PLAN_ID); print(p.credits if p else 50)" | head -1 || echo "50")
fi
export WEBHOOK_WAIT="$WEBHOOK_WAIT"

_setup() {
    _load_stripe_key
    _detect_base_url
    _detect_flask_env
    _ensure_tokens
    _detect_stripe_ids
}

# ---------------------------------------------------------------------------
# Cleanup — wipe all membership state (DB + Stripe). Base for any restore mode.
# ---------------------------------------------------------------------------

_cmd_cleanup() {
    echo "Cleaning up membership state (user=$TEST_USER_ID)..." >&2

    # DB: cascade delete in FK-safe order (single-line to avoid heredoc issues in _db_query)
    _db_query "uid=$TEST_USER_ID; CreditAllocation.query.filter(CreditAllocation.credit_transaction_id.in_(db.session.query(CreditTransaction.id).filter_by(user_id=uid))).delete(synchronize_session='fetch'); CreditNoteEvent.query.filter(CreditNoteEvent.credit_note_id.in_(db.session.query(CreditNote.id).filter_by(created_by_id=uid))).delete(synchronize_session='fetch'); CreditNote.query.filter_by(created_by_id=uid).delete(); mh=MembershipHistory.query.filter_by(user_id=uid).delete(); ct=CreditTransaction.query.filter_by(user_id=uid).delete(); ps=PaymentSubscription.query.filter_by(user_id=uid).delete(); u=User.query.get(uid); u.credits=0; u.subscription_plan_id=None; db.session.commit(); print(f'Cleaned: mh={mh} tx={ct} ps={ps} credits->0')"

    # Cancel all Stripe subs for this customer
    local subs
    subs=$(curl -s "https://api.stripe.com/v1/subscriptions?customer=$CUSTOMER_ID&status=all" \
        -u "$STRIPE_KEY:" | python3 -c "
import sys,json
for s in json.load(sys.stdin)['data']:
    if s['status'] in ('active','past_due','trialing'):
        print(s['id'])" 2>/dev/null)
    while IFS= read -r sub; do
        [[ -z "$sub" ]] && continue
        echo "Cancelling Stripe sub: $sub" >&2
        curl -s -X DELETE "https://api.stripe.com/v1/subscriptions/$sub" -u "$STRIPE_KEY:" >/dev/null
        sleep 1
    done <<< "$subs"

    echo "Cleanup complete" >&2
}

# ---------------------------------------------------------------------------
# Activate local — create membership in DB only (no Stripe sub). For one-time tests.
# Usage: --activate-local [--no-invoice]
# ---------------------------------------------------------------------------

_cmd_activate_local() {
    local skip_invoice="${1:-}"
    local with_inv="yes"
    [[ "$skip_invoice" == "--no-invoice" ]] && with_inv="no"
    echo "Activating local membership (user=$TEST_USER_ID, plan=$TEST_PLAN_ID, credits=$TEST_PLAN_CREDITS, invoice=$with_inv)..." >&2

    local skip_flag="False"
    [[ "$skip_invoice" == "--no-invoice" ]] && skip_flag="True"

    docker exec ironvolt-backend python3 -c "
from app import create_app
from models import *
from datetime import datetime, timedelta
app = create_app()
with app.app_context():
    uid, pid, credits, skip = $TEST_USER_ID, $TEST_PLAN_ID, $TEST_PLAN_CREDITS, $skip_flag
    plan = SubscriptionPlan.query.get(pid)
    user = User.query.get(uid)
    user.subscription_plan_id = pid
    user.credits = credits
    invoice_id = None
    if not skip:
        inv = Invoice(user_id=uid, plan_id=pid, amount=plan.price, status='paid', credits_awarded=credits)
        db.session.add(inv)
        db.session.flush()
        invoice_id = inv.id
    tx = CreditTransaction(user_id=uid, amount=credits, direction='credit', source='membership_activation', subscription_plan_id=pid, description='Local activation: '+plan.name, balance_before=0, balance_after=credits, invoice_id=invoice_id)
    db.session.add(tx)
    db.session.flush()
    now = datetime.utcnow()
    expires = now + timedelta(days=plan.duration_days) if plan.duration_days else None
    mh = MembershipHistory(user_id=uid, subscription_plan_id=pid, action_type='activated', credits_delta=credits, credit_transaction_id=tx.id, invoice_id=invoice_id, status='active', auto_renew=False, occurred_at=now - timedelta(days=5), expires_at=expires)
    db.session.add(mh)
    db.session.commit()
    print(f'Activated: plan={plan.name} credits={credits} invoice_id={invoice_id} expires={expires}')
" 2>/dev/null | grep -v -E '^\[|^$|INFO|DEBUG|WARNING|ERROR|scheduler|BackgroundScheduler|TaskRegistry|logging_config|Storage|MinIO|Starting app|LegacyAPI' || true
}

# ---------------------------------------------------------------------------
# Restore membership (Stripe subscription + webhooks). For recurring tests.
# ---------------------------------------------------------------------------

_cmd_restore() {
    echo "Restoring membership (user=$TEST_USER_ID, plan=$TEST_PLAN_ID)..." >&2

    # Full cleanup first
    _cmd_cleanup

    # Create new subscription with metadata
    local sub_id
    sub_id=$(curl -s -X POST 'https://api.stripe.com/v1/subscriptions' \
        -u "$STRIPE_KEY:" \
        -d "customer=$CUSTOMER_ID" \
        -d "items[0][price]=$STRIPE_PRICE" \
        -d "default_payment_method=$PM_ID" \
        -d "metadata[user_id]=$TEST_USER_ID" \
        -d "metadata[plan_id]=$TEST_PLAN_ID" \
        -d "metadata[credits]=$TEST_PLAN_CREDITS" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
    echo "Created sub: $sub_id" >&2
    sleep 2

    # Resend subscription.created (always via stripe CLI — works in both dev and prod)
    local evt
    evt=$(curl -s "https://api.stripe.com/v1/events?type=customer.subscription.created&limit=1" \
        -u "$STRIPE_KEY:" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)
    /tmp/stripe events resend "$evt" --api-key "$STRIPE_KEY" >/dev/null 2>&1
    sleep "$WEBHOOK_WAIT"

    # Resend invoice.payment_succeeded
    evt=$(curl -s "https://api.stripe.com/v1/events?type=invoice.payment_succeeded&limit=1" \
        -u "$STRIPE_KEY:" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)
    /tmp/stripe events resend "$evt" --api-key "$STRIPE_KEY" >/dev/null 2>&1
    sleep "$WEBHOOK_WAIT"

    # Refresh token before verify (restore can take >20min with retries)
    _refresh_tokens

    # Verify
    curl -sk "${BASE_URL}/api/subscriptions/my-subscription" \
        -H "Authorization: Bearer $ADMIN_TOKEN" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(f'Restored: active={d[\"has_subscription\"]}')" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Main — setup + eval, nothing else
# ---------------------------------------------------------------------------

case "${1:-}" in
    --help|-h)
        cat <<'HELP'
mt.sh — Manual Test Executor (middleware)

Prepares the environment and executes your command. That's it.

USAGE:
  ./scripts/mt.sh '<any bash command>'      Setup env, then eval the command
  ./scripts/mt.sh --env                     Show all detected variables
  ./scripts/mt.sh --db '<python code>'      Run python in backend (log-filtered)
  ./scripts/mt.sh --restore                 Restore recurring membership (Stripe + DB + webhooks)
  ./scripts/mt.sh --cleanup                 Wipe all membership state (DB + Stripe)
  ./scripts/mt.sh --activate-local          Create membership in DB only (no Stripe sub)
  ./scripts/mt.sh --activate-local --no-invoice   Same but without invoice (admin activation)
  ./scripts/mt.sh --reset-credits           Reset test user credits to 0
  ./scripts/mt.sh --refresh                 Force token refresh

SETUP RECIPES:
  Recurring (J1/J2/J5/J6/J7):  --restore
  One-time  (J3/J4):           --cleanup && --activate-local
  Admin+Sub (J8):              --cleanup && --activate-local --no-invoice
                               then create Stripe sub manually

VARIABLES (available inside your command):
  $BASE_URL  $ADMIN_TOKEN  $CLIENT_TOKEN  $STRIPE_KEY
  $CUSTOMER_ID  $PM_ID  $STRIPE_PRICE
  $TEST_USER_ID  $TEST_PLAN_ID  $FLASK_ENV  $WEBHOOK_WAIT
HELP
        exit 0
        ;;
    --env)
        _setup
        echo "BASE_URL=$BASE_URL"
        echo "FLASK_ENV=$FLASK_ENV"
        echo "ADMIN_TOKEN=${ADMIN_TOKEN:0:20}..."
        echo "CLIENT_TOKEN=${CLIENT_TOKEN:0:20}..."
        echo "STRIPE_KEY=${STRIPE_KEY:0:12}..."
        echo "CUSTOMER_ID=$CUSTOMER_ID"
        echo "PM_ID=$PM_ID"
        echo "STRIPE_PRICE=$STRIPE_PRICE"
        echo "TEST_USER_ID=$TEST_USER_ID"
        echo "TEST_PLAN_ID=$TEST_PLAN_ID"
        echo "TEST_PLAN_CREDITS=$TEST_PLAN_CREDITS"
        ;;
    --restore)
        _setup
        _cmd_restore
        ;;
    --cleanup)
        _setup
        _cmd_cleanup
        ;;
    --activate-local)
        _setup
        _cmd_activate_local "${2:-}"
        ;;
    --reset-credits)
        _setup
        _db_query "
from services.credit_service import CreditService
cs = CreditService()
s = cs.get_credit_summary($TEST_USER_ID)
t = s.data.get('total_available',0) if s.success else 0
if t > 0:
    cs.debit_credits($TEST_USER_ID, t, 'manual_reset', 'Test reset')
    db.session.commit()
print(f'Credits: {t} -> 0')
"
        ;;
    --refresh)
        _load_stripe_key
        _detect_base_url
        _refresh_tokens
        echo "Done"
        ;;
    --db)
        _setup
        _db_query "$2"
        ;;
    "")
        echo "Usage: ./scripts/mt.sh '<command>' | --env | --db | --restore | --cleanup | --activate-local | --reset-credits | --refresh" >&2
        exit 1
        ;;
    *)
        _setup
        eval "$*"
        ;;
esac
