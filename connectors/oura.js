const axios = require('axios');

async function execute(userId, action, params) {
  const token = process.env.OURA_ACCESS_TOKEN;
  if (!token) {
    return { success: false, outcome: 'unavailable', unavailable: true, error: `Oura ${action} is unavailable because Oura is not connected.` };
  }

  const headers = { Authorization: `Bearer ${token}` };

  try {
    const startDate = params.start_date || new Date(Date.now() - 86400000 * 7).toISOString().split('T')[0];
    if (action === 'get_oura_sleep') {
      // `sleep` is the period endpoint and carries no score; daily_sleep does.
      const res = await axios.get(`https://api.ouraring.com/v2/usercollection/daily_sleep?start_date=${startDate}`, { headers, timeout: 15000 });
      const latest = res.data.data?.[res.data.data.length - 1];
      const hours = latest?.total_sleep_duration ? (latest.total_sleep_duration / 3600).toFixed(1) : null;
      return {
        success: true,
        text: `Oura latest sleep: score ${latest?.score ?? 'N/A'}${hours ? `, ${hours}h asleep` : ''}`,
        score: latest?.score ?? null
      };
    }
    if (action === 'get_oura_readiness') {
      const res = await axios.get(`https://api.ouraring.com/v2/usercollection/daily_readiness?start_date=${startDate}`, { headers, timeout: 15000 });
      const latest = res.data.data?.[res.data.data.length - 1];
      return { success: true, text: `Oura readiness: ${latest?.score ?? 'N/A'}`, score: latest?.score ?? null };
    }
    return { success: false, error: 'Unknown Oura action' };
  } catch (e) {
    return { success: false, error: `Oura error: ${e.response?.data?.detail || e.message}` };
  }
}

module.exports = { execute };
