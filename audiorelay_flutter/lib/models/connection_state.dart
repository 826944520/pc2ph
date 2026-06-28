/// Connection state machine.
enum ConnectionState {
  disconnected,
  discovering,
  connecting,
  connected,
  streaming,
  reconnecting,
  error,
}
