const UNAVAILABLE_ERROR = 'That capability is not available yet. No action was taken.';
const DISABLED_ERROR = 'This connection is disabled. Re-enable it in Settings before trying again.';

function createDeclaredAdapterInvoker({
  executeInline,
  dispatchConnector,
  getEnabledConnectors = async () => []
}) {
  if (typeof executeInline !== 'function') throw new TypeError('createDeclaredAdapterInvoker requires executeInline');
  if (typeof dispatchConnector !== 'function') throw new TypeError('createDeclaredAdapterInvoker requires dispatchConnector');

  return async function invokeDeclaredAdapter({ adapter, userId, type, input, context = {} }) {
    // The model's own argument wins: a hotel search asks for "Bath", not the device's
    // {latitude, longitude}. GPS is only a fallback for actions that did not name a place.
    const given = input || {};
    const enrichedInput = {
      ...given,
      ...(context.location && given.location == null ? { location: context.location } : {}),
      ...(context.homeLocation && given.homeLocation == null ? { homeLocation: context.homeLocation } : {})
    };

    if (adapter?.kind === 'inline') {
      return executeInline({ userId, type, input: enrichedInput, context });
    }

    if (adapter?.kind === 'connector') {
      if (adapter.requiresConnection === true) {
        const enabledConnectors = Array.isArray(context.enabledConnectors)
          ? context.enabledConnectors
          : await getEnabledConnectors(userId, context.trace || null);
        if (!enabledConnectors.includes(adapter.id)) {
          return { success: false, outcome: 'unavailable', unavailable: true, error: DISABLED_ERROR };
        }
      }
      return dispatchConnector({ connectorId: adapter.id, userId, type, input: enrichedInput, context });
    }

    return { success: false, outcome: 'unavailable', unavailable: true, error: UNAVAILABLE_ERROR };
  };
}

module.exports = {
  createDeclaredAdapterInvoker,
  UNAVAILABLE_ERROR,
  DISABLED_ERROR
};
