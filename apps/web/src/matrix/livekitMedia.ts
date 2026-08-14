import { Room, RoomEvent, type BaseKeyProvider } from "livekit-client";
import type { LivekitMediaSession } from "./matrixRtc";

function createLivekitE2eeWorker(): Worker {
  return new Worker(new URL("livekit-client/e2ee-worker", import.meta.url), { type: "module" });
}

export class BrowserLivekitMedia implements LivekitMediaSession {
  private room: Room | null = null;
  private mixed: MediaStream | null = null;
  private local: MediaStream | null = null;
  private readonly listeners = new Set<() => void>();

  async connect(url: string, token: string, options?: { keyProvider?: BaseKeyProvider }): Promise<void> {
    await this.disconnect();
    const keyProvider = options?.keyProvider;
    const room = new Room({
      encryption: keyProvider
        ? {
            keyProvider,
            worker: createLivekitE2eeWorker(),
          }
        : undefined,
      publishDefaults: {
        // LiveKit SFU strips RED for clients that cannot decode it; that breaks E2EE.
        red: false,
      },
    });
    this.room = room;
    room.on(RoomEvent.TrackSubscribed, () => this.rebuildRemote());
    room.on(RoomEvent.TrackUnsubscribed, () => this.rebuildRemote());
    room.on(RoomEvent.Disconnected, () => this.rebuildRemote());
    if (keyProvider) await room.setE2EEEnabled(true);
    await room.connect(url, token);
    this.rebuildRemote();
    this.rebuildLocal();
  }

  async disconnect(): Promise<void> {
    const room = this.room;
    this.room = null;
    this.mixed = null;
    this.local = null;
    if (room) await room.disconnect(true);
    this.emit();
  }

  async setMicrophoneEnabled(enabled: boolean): Promise<void> {
    await this.room?.localParticipant.setMicrophoneEnabled(enabled);
    this.rebuildLocal();
  }

  async setCameraEnabled(enabled: boolean): Promise<void> {
    await this.room?.localParticipant.setCameraEnabled(enabled);
    this.rebuildLocal();
  }

  remoteStream(): MediaStream | null {
    return this.mixed;
  }

  localStream(): MediaStream | null {
    return this.local;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private rebuildRemote(): void {
    const tracks: MediaStreamTrack[] = [];
    for (const participant of this.room?.remoteParticipants.values() ?? []) {
      for (const publication of [...participant.audioTrackPublications.values(), ...participant.videoTrackPublications.values()]) {
        const track = publication.track;
        if (track?.mediaStreamTrack) tracks.push(track.mediaStreamTrack);
      }
    }
    this.mixed = tracks.length > 0 ? new MediaStream(tracks) : null;
    this.emit();
  }

  private rebuildLocal(): void {
    const tracks: MediaStreamTrack[] = [];
    const participant = this.room?.localParticipant;
    if (participant) {
      for (const publication of [...participant.audioTrackPublications.values(), ...participant.videoTrackPublications.values()]) {
        const track = publication.track;
        if (track?.mediaStreamTrack) tracks.push(track.mediaStreamTrack);
      }
    }
    this.local = tracks.length > 0 ? new MediaStream(tracks) : null;
    this.emit();
  }

  private emit(): void {
    for (const listener of this.listeners) listener();
  }
}
