import { useState, useSyncExternalStore } from "react";
import { DirectCallSurface } from "./components/DirectCallSurface";
import { MatrixRtcSurface } from "./components/MatrixRtcSurface";
import { GroupCallSurface } from "./components/Surfaces";
import { LoginScreen } from "./components/LoginScreen";
import { Workspace } from "./components/Workspace";
import { useI18n } from "./i18n";
import { useBootstrap, useMatrix } from "./matrix/hooks";
import {
  acceptDirectCall,
  getDirectCallSnapshot,
  getMatrixRtcSnapshot,
  hangupDirectCall,
  leaveMatrixRtc,
  rejectDirectCall,
  subscribeDirectCall,
  subscribeMatrixRtc,
  toggleDirectCallMicrophone,
  toggleMatrixRtcMicrophone,
} from "./matrix/service";

export function App() {
  const ready = useBootstrap();
  const matrix = useMatrix();
  const { t } = useI18n();
  const [elementCallRoomId, setElementCallRoomId] = useState<string | null>(null);
  const directCall = useSyncExternalStore(
    subscribeDirectCall,
    getDirectCallSnapshot,
    getDirectCallSnapshot,
  );
  const matrixRtc = useSyncExternalStore(
    subscribeMatrixRtc,
    getMatrixRtcSnapshot,
    getMatrixRtcSnapshot,
  );

  if (!ready) {
    return (
      <main className="boot" aria-live="polite">
        <span className="brand-symbol" aria-hidden="true">H</span>
        <strong>{t("app.opening")}</strong>
        <span>{t("app.preparing")}</span>
      </main>
    );
  }

  return (
    <>
      {matrix.client ? <Workspace /> : <LoginScreen initialError={matrix.error} />}
      <DirectCallSurface
        snapshot={directCall}
        labels={{
          dialog: t("call.dialog"),
          connected: t("call.connected"),
          incoming: t("call.incoming"),
          failed: t("call.failed"),
          connecting: t("call.connecting"),
          unknownPeer: t("call.unknownPeer"),
          answer: t("call.answer"),
          decline: t("call.decline"),
          mute: t("call.mute"),
          unmute: t("call.unmute"),
          hangup: t("call.hangup"),
          micBlocked: t("call.micBlocked"),
        }}
        onAccept={() => void acceptDirectCall()}
        onReject={rejectDirectCall}
        onHangup={hangupDirectCall}
        onToggleMicrophone={() => void toggleDirectCallMicrophone()}
      />
      <MatrixRtcSurface
        snapshot={matrixRtc}
        labels={{
          dialog: t("call.dialog"),
          connecting: t("call.connecting"),
          connected: t("call.connected"),
          failed: t("call.failed"),
          mute: t("call.mute"),
          unmute: t("call.unmute"),
          hangup: t("call.hangup"),
          fallback: t("call.fallback"),
          participants: t("call.participants"),
        }}
        onHangup={() => void leaveMatrixRtc()}
        onToggleMicrophone={() => void toggleMatrixRtcMicrophone()}
        onFallback={() => {
          const roomId = matrixRtc.roomId;
          void leaveMatrixRtc();
          if (roomId) setElementCallRoomId(roomId);
        }}
      />
      {elementCallRoomId && (
        <GroupCallSurface roomId={elementCallRoomId} onClose={() => setElementCallRoomId(null)} />
      )}
    </>
  );
}
