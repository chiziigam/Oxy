'use strict';

// Display and visual-generation actions, lifted out of the switch in api/index.js.
//
// generateImage stays owned by index.js and arrives through deps: it is the outermost
// model/image boundary and belongs bound in one place.

async function listPairedDisplays({ userId, action, params, enrichedParams, context, deps, helpers }) {
  const { supabase, generateImage } = deps;
  const pairedDisplays = require('../services/paired-displays');
  const displays = await pairedDisplays.listDisplays(supabase, userId);
  return {
    success: true,
    displays,
    text: displays.length
      ? displays.map(display => display.name + ' (' + display.type + ')').join('\n')
      : 'No nearby displays are paired yet.'
  };
}

async function renderToDisplay({ userId, action, params, enrichedParams, context, deps, helpers }) {
  const { supabase, generateImage } = deps;
  const pairedDisplays = require('../services/paired-displays');
  const event = await pairedDisplays.queueRender(supabase, userId, {
    displayId: params?.display_id || params?.displayId,
    title: params?.title,
    body: params?.body,
    kind: params?.kind,
    scene: params?.scene
  });
  const delivery = await pairedDisplays.awaitDelivery(supabase, userId, event.id, deps.displayDelivery);
  if (delivery.shown) {
    return {
      success: true,
      outcome: 'completed',
      eventId: event.id,
      displayId: event.displayId,
      text: 'On the screen now: ' + event.title,
      actionSummary: 'Showing on display'
    };
  }
  // Queued is not shown. The screen takes it the next time it is on and online.
  return {
    success: false,
    outcome: 'incomplete',
    incomplete: true,
    eventId: event.id,
    displayId: event.displayId,
    text: (delivery.name || 'The screen') + ' has not picked that up yet; it will show when the screen is on and online.',
    actionSummary: 'Sent, not shown yet'
  };
}

async function showScene({ params }) {
  const title = String(params?.title || '').replace(/\s+/g, ' ').trim().slice(0, 120) || 'Adam';
  let srcdoc;
  let spec;
  try {
    spec = require('../services/scene-spec').validateScene(params?.scene);
    srcdoc = require('../services/scene-runtime').buildSpecDocument(spec);
  } catch (e) {
    return { success: false, outcome: 'failed', error: e.message };
  }
  return {
    success: true,
    outcome: 'completed',
    text: String(params?.body || title).replace(/\s+/g, ' ').trim().slice(0, 300),
    actionSummary: 'Made a page: ' + title,
    scene: { title, srcdoc, ...(spec.mode === 'interface' ? { spec } : {}) }
  };
}

// A small game or toy the user plays inside the app. The model writes one self-contained page; the
// phone runs it in a box with no network, no storage and no way back into the app (see
// PlayableGameCard). This checks the page is usable and that it is not reaching for the internet,
// so a page that could never work is sent back to be rewritten rather than shown broken.
const MAX_GAME_HTML = 60000;
const MIN_GAME_HTML = 40;

function cleanGameHtml(value) {
  return String(value)
    .replace(/<!doctype[^>]*>/gi, '')
    .replace(/<\/?(?:html|head|body)\b[^>]*>/gi, '')
    .trim();
}

function reachesTheInternet(html) {
  const withoutNamespaces = html.replace(/https?:\/\/www\.w3\.org\/[^\s"'<>)]*/gi, '');
  return /\b(?:fetch|XMLHttpRequest|WebSocket|EventSource|sendBeacon|importScripts)\b/.test(withoutNamespaces)
    || /(?:https?:)?\/\/[a-z0-9-]+\.[a-z]{2,}/i.test(withoutNamespaces)
    || /\b(?:localStorage|sessionStorage|indexedDB|document\.cookie)\b/.test(withoutNamespaces);
}

async function makeGame({ params } = {}) {
  const title = String(params?.title || '').replace(/\s+/g, ' ').trim().slice(0, 80) || 'Game';
  if (typeof params?.html !== 'string') {
    return { success: false, outcome: 'failed', error: 'make_game needs html: the page body as one string.' };
  }
  const html = cleanGameHtml(params.html);
  if (html.length < MIN_GAME_HTML) {
    return { success: false, outcome: 'failed', error: 'That page is too short to be a game. Send the whole page.' };
  }
  if (html.length > MAX_GAME_HTML) {
    return { success: false, outcome: 'failed', error: `That page is too long (${html.length} characters; the limit is ${MAX_GAME_HTML}). Make the game smaller.` };
  }
  if (reachesTheInternet(html)) {
    return {
      success: false,
      outcome: 'failed',
      error: 'A game runs with no internet and no saved data. Remove fetch, XMLHttpRequest, WebSocket, web addresses, localStorage, sessionStorage, indexedDB and cookies, and keep everything inside the page.'
    };
  }
  return {
    success: true,
    outcome: 'completed',
    text: `Made a game: ${title}. Tap Play to open it.`,
    actionSummary: 'Made a game: ' + title,
    playable: { title, html }
  };
}

async function getDisplayScene({ userId, params, deps }) {
  const { supabase } = deps;
  const pairedDisplays = require('../services/paired-displays');
  const scene = await pairedDisplays.currentScene(supabase, userId, params?.display_id || params?.displayId);
  if (!scene) return { success: true, found: false, text: 'That screen is not showing a page.' };
  return {
    success: true,
    found: true,
    title: scene.title,
    body: scene.body,
    scene: scene.scene,
    text: 'The screen is showing: ' + scene.title
  };
}

async function generateVisual({ userId, action, params, enrichedParams, context, deps, helpers }) {
  const { supabase, generateImage } = deps;
  const brief = params?.brief || params?.prompt || params?.topic;
  if (!brief) return { success: false, error: 'generate_visual needs a brief.' };
  const prompt = [
    brief,
    params?.style ? `Style: ${params.style}` : '',
    params?.usage ? `Usage: ${params.usage}` : ''
  ].filter(Boolean).join('\n');
  const visual = await generateImage(prompt, context.imageFile || null);
  return {
    success: true,
    text: visual.text || 'I made a visual for this.',
    artifact: {
      type: 'image',
      title: params?.usage || 'Generated visual',
      image: visual.image,
      mimeType: visual.mimeType
    }
  };
}

async function createDiagram({ params, context, deps }) {
  return deps.createDiagramArtifact(params || {}, context.imageFile || null);
}

async function createPresentation({ params, context, deps }) {
  return deps.createPresentationArtifact(params || {}, context.imageFile || null);
}

module.exports = {
  handlers: {
    create_diagram: createDiagram,
    create_presentation: createPresentation,
    list_paired_displays: listPairedDisplays,
    render_to_display: renderToDisplay,
    get_display_scene: getDisplayScene,
    show_scene: showScene,
    generate_visual: generateVisual,
    make_game: makeGame
  }
};
