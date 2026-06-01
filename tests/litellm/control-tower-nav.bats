#!/usr/bin/env bats
# Control Tower navigation regression tests.
#
# The Control Tower is a multi-page Next.js app. Every page must expose the
# full nav so the operator can move between sections. These tests guard
# against a page dropping a nav link (regression seen in #173).
#
# The #181 redesign consolidated the previously-inline, per-page nav into a
# single shared `TopNav` component (one source of truth). The regression class
# from #173 (a page silently dropping a link) is now structurally prevented:
# pages render <TopNav/> rather than re-declaring the link set. These tests are
# updated to guard the new architecture — the shared nav carries the full link
# set, and every canonical page renders it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CT="$REPO_ROOT/apps/control-tower/app"
  TOPNAV="$CT/components/ui/TopNav.tsx"
}

@test "Control Tower nav includes Content link" {
  # The shared TopNav must carry the /content link (and exist).
  [ -f "$TOPNAV" ]
  run grep -q 'href: "/content"' "$TOPNAV"
  [ "$status" -eq 0 ]
}

@test "Control Tower TopNav carries the full canonical link set" {
  # Guard against silently dropping any section from the shared nav.
  for href in "/" "/council" "/ideation" "/history" "/content"; do
    run grep -F "href: \"$href\"" "$TOPNAV"
    [ "$status" -eq 0 ]
  done
}

@test "Control Tower canonical pages render the shared TopNav" {
  # Every canonical page must render <TopNav/> so the operator always has the
  # full nav. This replaces the pre-redesign per-page inline-nav check.
  for page in page.tsx council/page.tsx ideation/page.tsx history/page.tsx content/page.tsx; do
    run grep -q 'TopNav' "$CT/$page"
    [ "$status" -eq 0 ]
  done
}
