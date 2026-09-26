#include "native/audio/endpoint_mute_policy.h"

#include <cassert>

int main() {
  using pctv::EndpointMutePolicy;

  EndpointMutePolicy policy;

  // An initially unmuted endpoint is restored only while our mute is intact.
  policy.Begin(false);
  policy.RecordAppChange(true);
  assert(policy.ShouldRestore(true));
  assert(!policy.ShouldRestore(false));
  policy.End();

  // Preserve mute when it was already enabled before mirroring.
  policy.Begin(true);
  assert(!policy.changed_by_app());
  assert(!policy.ShouldRestore(true));
  policy.End();

  // Never overwrite a mute or unmute action made outside the application.
  policy.Begin(false);
  policy.RecordAppChange(true);
  policy.RecordExternalChange();
  assert(!policy.ShouldRestore(true));
  assert(!policy.ShouldRestore(false));
  policy.End();
  assert(policy.external_override());
  assert(!policy.changed_by_app());

  // A later opt-in starts a fresh restoration transaction.
  policy.Begin(false);
  policy.RecordAppChange(true);
  assert(policy.ShouldRestore(true));
  return 0;
}
