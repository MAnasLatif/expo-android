#!/usr/bin/env bash
# =============================================================================
# Remove resources that belong to THIS environment only.
#
#   scripts/cleanup.sh --containers           stop + remove the container
#   scripts/cleanup.sh --project [PATH]       remove one project's node_modules volume
#   scripts/cleanup.sh --caches               remove all env volumes (node_modules, bun/expo/gradle caches)
#   scripts/cleanup.sh --image                remove the expo-android-env image
#   scripts/cleanup.sh --sdk                  delete the isolated SDK + AVD ($ENV_HOME)
#   scripts/cleanup.sh --all                  all of the above (full uninstall)
#   add --yes to skip the confirmation prompt
#
# Safety: Docker resources are selected by the label
# com.expo-android-env.managed=true AND the expo-android-env name prefix.
# $ENV_HOME is only deleted if it contains the marker file written by setup.
# Your projects, other containers/images/volumes and other SDKs are never touched.
# =============================================================================
source "$(dirname "$0")/lib/common.sh"
load_config

DO_CONT=0 DO_PROJ=0 DO_CACHE=0 DO_IMAGE=0 DO_SDK=0 YES=0 PROJ_ARG=""
[ $# -gt 0 ] || { sed -n '2,17p' "$0"; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --containers) DO_CONT=1 ;;
    --project) DO_PROJ=1; if [ -n "${2:-}" ] && [ "${2#--}" = "$2" ]; then PROJ_ARG="$2"; shift; fi ;;
    --caches) DO_CACHE=1 ;;
    --image) DO_IMAGE=1 ;;
    --sdk) DO_SDK=1 ;;
    --all) DO_CONT=1; DO_CACHE=1; DO_IMAGE=1; DO_SDK=1 ;;
    --yes|-y) YES=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac; shift
done
# Volumes and images can't be removed while the container uses them.
if [ "$DO_PROJ$DO_CACHE$DO_IMAGE" != 000 ]; then DO_CONT=1; fi

# --- 1. Build the plan (nothing is deleted yet) -----------------------------------
PLAN_CONTAINER="" PLAN_VOLUMES="" PLAN_IMAGE="" PLAN_SDK=""

if [ "$DO_CONT$DO_PROJ$DO_CACHE$DO_IMAGE" != 0000 ]; then
  require_docker
  if [ "$DO_CONT" = 1 ] && docker ps -aq --filter "label=$LABEL" --filter "name=^${CONTAINER_NAME}$" | grep -q .; then
    PLAN_CONTAINER="$CONTAINER_NAME"
  fi
  if [ "$DO_CACHE" = 1 ]; then
    # Only volumes with BOTH our label and our name prefix.
    PLAN_VOLUMES="$(docker volume ls -q --filter "label=$LABEL" | grep '^expo-android-env_' || true)"
  elif [ "$DO_PROJ" = 1 ]; then
    resolve_project "$PROJ_ARG"
    vol="expo-android-env_node_modules_$PROJECT_SLUG"
    if docker volume inspect "$vol" >/dev/null 2>&1; then PLAN_VOLUMES="$vol"; fi
  fi
  if [ "$DO_IMAGE" = 1 ] && docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    PLAN_IMAGE="$IMAGE_NAME"
  fi
fi

if [ "$DO_SDK" = 1 ] && [ -d "$ENV_HOME" ]; then
  # Guard against a mis-set ENV_HOME (/, $HOME, or a folder setup didn't create).
  if [ ! -f "$ENV_HOME/.expo-android-env-root" ] || [ "$ENV_HOME" = "$HOME" ] || [ "$ENV_HOME" = "/" ]; then
    die "Refusing to delete $ENV_HOME: marker file .expo-android-env-root not found (not created by setup.sh)"
  fi
  PLAN_SDK="$ENV_HOME"
fi

# --- 2. Show the plan and confirm once ----------------------------------------
if [ -z "$PLAN_CONTAINER$PLAN_VOLUMES$PLAN_IMAGE$PLAN_SDK" ]; then
  ok "Nothing to remove"; exit 0
fi
echo "The following will be removed:" >&2
[ -n "$PLAN_CONTAINER" ] && echo "   container  $PLAN_CONTAINER" >&2
[ -n "$PLAN_VOLUMES" ]   && echo "$PLAN_VOLUMES" | sed 's/^/   volume     /' >&2
[ -n "$PLAN_IMAGE" ]     && echo "   image      $PLAN_IMAGE" >&2
[ -n "$PLAN_SDK" ]       && echo "   folder     $PLAN_SDK ($(du -sh "$PLAN_SDK" 2>/dev/null | cut -f1)) — emulator, system image, AVD" >&2

if [ "$YES" != 1 ]; then
  [ -t 0 ] || die "Refusing to delete without confirmation in a non-interactive shell (add --yes)."
  read -r -p "Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy] ]] || { warn "Aborted — nothing removed"; exit 1; }
fi

# --- 3. Execute ----------------------------------------------------------------------
if [ -n "$PLAN_CONTAINER" ]; then
  docker rm -f "$PLAN_CONTAINER" >/dev/null && ok "Removed container $PLAN_CONTAINER"
fi
if [ -n "$PLAN_VOLUMES" ]; then
  # shellcheck disable=SC2086
  docker volume rm $PLAN_VOLUMES >/dev/null && ok "Removed $(echo "$PLAN_VOLUMES" | wc -l | tr -d ' ') volume(s)"
fi
if [ -n "$PLAN_IMAGE" ]; then
  docker image rm "$PLAN_IMAGE" >/dev/null && ok "Removed image $PLAN_IMAGE"
fi
if [ -n "$PLAN_SDK" ]; then
  "$(dirname "$0")/emulator-stop.sh" >/dev/null 2>&1 || true
  rm -rf "$PLAN_SDK" && ok "Removed $PLAN_SDK"
fi
