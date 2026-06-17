const playbackCommandSettleDuration = Duration(milliseconds: 250);
const playCommandDispatchTimeout = Duration(milliseconds: 1200);

bool isPlaybackStartConfirmed({
  required bool requestActive,
  required bool playerPlaying,
  required bool processingReady,
  required Duration elapsedSinceCommand,
}) {
  return requestActive &&
      playerPlaying &&
      processingReady &&
      elapsedSinceCommand >= playbackCommandSettleDuration;
}
