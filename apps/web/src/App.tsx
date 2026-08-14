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
  dismissIncomingRtcCall,
  getDirectCallSnapshot,
  getIncomingRtcCall,
  getMatrixRtcSnapshot,
  hangupDirectCall,
  leaveMatrixRtc,
  rejectDirectCall,
  startMatrixRtc,
  subscribeDirectCall,
  subscribeMatrixRtc,
  toggleDirectCallMicrophone,
  toggleDirectCallCamera,
  toggleMatrixRtcMicrophone,
  toggleMatrixRtcCamera,
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

  const incomingRtc = getIncomingRtcCall();

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
      {incomingRtc && matrixRtc.phase === "idle" && (directCall.phase === "idle" || directCall.phase === "ended") && (
        <section className="direct-call" role="dialog" aria-label={t("call.dialog")}>
          <div className="direct-call-copy">
            <strong>{incomingRtc.name}</strong>
            <span>{t("call.incoming")}</span>
          </div>
          <div className="direct-call-actions">
            <button
              type="button"
              className="button call-answer"
              onClick={() => void startMatrixRtc(incomingRtc.roomId)}
            >
              {t("call.answer")}
            </button>
            <button
              type="button"
              className="button danger"
              onClick={() => dismissIncomingRtcCall(incomingRtc.roomId)}
            >
              {t("call.decline")}
            </button>
          </div>
        </section>
      )}
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
          cameraOn: t("call.cameraOn"),
          cameraOff: t("call.cameraOff"),
        }}
        onAccept={() => void acceptDirectCall()}
        onReject={rejectDirectCall}
        onHangup={hangupDirectCall}
        onToggleMicrophone={() => void toggleDirectCallMicrophone()}
        onToggleCamera={() => void toggleDirectCallCamera()}
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
          cameraOn: t("call.cameraOn"),
          cameraOff: t("call.cameraOff"),
        }}
        onHangup={() => void leaveMatrixRtc()}
        onToggleMicrophone={() => void toggleMatrixRtcMicrophone()}
        onToggleCamera={() => void toggleMatrixRtcCamera()}
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
