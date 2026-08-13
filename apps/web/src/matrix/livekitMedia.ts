import { Room, RoomEvent, Track } from "livekit-client";
import type { LivekitMediaSession } from "./matrixRtc";

export class BrowserLivekitMedia implements LivekitMediaSession {
  private room: Room | null = null;
  private mixed: MediaStream | null = null;
  private readonly listeners = new Set<() => void>();

  async connect(url: string, token: string): Promise<void> {
    await this.disconnect();
    const room = new Room();
    this.room = room;
    room.on(RoomEvent.TrackSubscribed, () => this.rebuildRemote());
    room.on(RoomEvent.TrackUnsubscribed, () => this.rebuildRemote());
    room.on(RoomEvent.Disconnected, () => this.rebuildRemote());
    await room.connect(url, token);
    this.rebuildRemote();
  }

  async disconnect(): Promise<void> {
    const room = this.room;
    this.room = null;
    this.mixed = null;
    if (room) await room.disconnect(true);
    this.emit();
  }

  async setMicrophoneEnabled(enabled: boolean): Promise<void> {
    await this.room?.localParticipant.setMicrophoneEnabled(enabled);
  }

  remoteStream(): MediaStream | null {
    return this.mixed;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private rebuildRemote(): void {
    const tracks: MediaStreamTrack[] = [];
    for (const participant of this.room?.remoteParticipants.values() ?? []) {
      for (const publication of participant.audioTrackPublications.values()) {
        const track = publication.track;
        if (track?.kind === Track.Kind.Audio && track.mediaStreamTrack) {
          tracks.push(track.mediaStreamTrack);
        }
      }
    }
    this.mixed = tracks.length > 0 ? new MediaStream(tracks) : null;
    this.emit();
  }

  private emit(): void {
    for (const listener of this.listeners) listener();
  }
}
