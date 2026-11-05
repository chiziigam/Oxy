# Product scope

The design is in DESIGN.md. This file is the product scope and status only.

## Product scope checklist

This is the full product scope. Physical hardware is part of the north star, but
software work comes first.

1. **Physical Device**
   - Always-available hardware.
   - Far-field microphone array.
   - Speaker and audio output.
   - Wake word or low-friction activation.
   - Physical privacy control, such as a mute switch or shutter indicator.
   - Premium design that belongs in the home.
   - Low power use for always-on operation.
   - Secure hardware identity.
   - Device-level encryption.
   - Over-the-air firmware updates.

2. **Agent Operating System**
   - Persistent agent identity: Adam.
   - Long-term memory.
   - User profile and preferences.
   - Goals.
   - Relationships and context.
   - Understanding of the person's life.

3. **Personal AI Workspace**
   - Dedicated storage.
   - Filesystem.
   - Browser environment.
   - Project folders.
   - Task history.
   - Working memory.
   - Persistent sessions.

4. **Model Independence**
   - Supported connections to ChatGPT, Claude, Gemini, and local models.
   - Model routing.
   - The user owns the relationship with their chosen AI services.

5. **AI Account Migration and Continuity**
   - Connect existing AI accounts where supported.
   - Import conversations, projects, instructions, and documents.
   - Convert imported history into memory.
   - Preserve the user's relationship with AI without making them start again.

6. **Tool Ecosystem**
   - Communication: email, messages, eventual phone calls, and contacts.
   - Productivity: calendar, notes, documents, tasks, and reminders.
   - Development: GitHub, IDE environments, code execution, and deployment tools.
   - Everyday life: shopping, travel booking, careful banking visibility, smart home, and subscriptions.

7. **Browser Agent**
   - Its own browser.
   - Persistent sessions.
   - Login management.
   - Website understanding.
   - Form completion.
   - Checkout capability.
   - Research ability.

8. **Permission System**
   - Read permissions.
   - Write permissions.
   - Approval requirements.
   - Action history.
   - Undo capability.
   - Audit logs.

9. **Agent Execution Engine**
   - Multi-step planning.
   - Background tasks.
   - Scheduling.
   - Monitoring.
   - Follow-ups.
   - Notifications.
   - Example: Adam checks flight prices on a schedule and alerts the user when she finds a better option.

10. **Voice Intelligence**
    - Natural conversation.
    - Interruptions.
    - Retained context.
    - Fast responses.
    - Multiple voices and personality options.
    - Ability to whisper or speak quietly.
    - Optional understanding of the surroundings.

11. **Multi-device Presence**
    - Home device.
    - Phone app.
    - Laptop companion.
    - Car integration.
    - Wearable.
    - The same Adam identity everywhere.

12. **Security and Trust**
    - Encryption.
    - User-owned data.
    - Clear history and transparent logs.
    - Data export.
    - A delete-everything option.
    - Local processing where possible.
    - Secure authentication.

## Current real-life status — 6 August 2026

Supersedes the 5 August audit (which never left a scratch worktree and understated
three items that were fixed the same week). Each line is graded on what a person can
actually do today, not what exists in code. "Verified" means checked directly this
session — a real build, a live request, a database write, or a production log, not a
report taken on trust.

1. **Physical Device — Missing, by choice.** Explicitly deferred; no hardware exists.
2. **Agent Operating System — Partly built.** Durable per-goal execution sessions
   (`agent_runtime_sessions`) are live in production and verified with a real write.
   Memory, preferences, and a simplified "About You" profile screen exist. Not proven
   as dependable everyday help — still early.
3. **Personal AI Workspace — Missing for a person.** The storage/session tables exist
   but hold no real content, and the project-diff/runtime-inspection surface that used
   to sit on top of it was developer tooling, not a consumer feature — removed from
   navigation this session.
4. **Model Independence — Missing.** Provider routing is server-configured only; a
   person cannot connect their own ChatGPT/Claude/Gemini account. The "AI choices"
   screen was removed from navigation for the same reason.
5. **AI Account Migration and Continuity — Partly built.** Real ChatGPT/Claude
   conversation import and Zapier-routine conversion shipped and passed tests
   (213c51c1); not yet proven against a real person's actual export.
6. **Tool Ecosystem — Partly built.** The general appointment-booking flow (not
   dentist-specific) was proven end-to-end live in the signed-in app this week:
   choices offered, explicit approval required, one booking made, calendar entry
   added, confirmation shown on Home. Sandbox-only — no real practice contacted yet.
   Email/calendar context and reminders are real; banking visibility, smart home, and
   subscriptions are not started.
7. **Browser Agent — Partly built, the most mature area.** Persistent sessions, login
   management, and real checkout have completed live purchases in production
   (verified in prod, not just locally). Some sites remain blocked by bot walls
   (Magento/BigCommerce, some Nike-class sites) with no viable path found yet.
8. **Permission System — Partly built.** Explicit-approval-before-action was proven
   live for the booking flow this week. A durable approval table
   (`agent_runtime_approvals`) now backs this in production, verified with a real
   write today. A permission-policy and audit-log screen ("Trust") is now reachable
   from Settings. Coverage across every action type is not audited.
9. **Agent Execution Engine — Partly built.** Background watches ("Adam is
   watching…") now surface as real cards on Home and in the task list, not just
   backend state. Dependable follow-through and notifications across a full week of
   real use is not proven.
10. **Voice Intelligence — Partly built.** Voice input/output runs on OpenAI TTS/STT
    in production. The product's core promise — say one sentence, get it handled — has
    only been proven through typed chat so far, not spoken.
11. **Multi-device Presence — Missing.** iPhone app only.
12. **Security and Trust — Partly built, meaningfully improved this week.** The live
    AI connection is healthy (was rejecting all requests as of 5 Aug; fixed and
    verified). Row-level security was closed on 6 previously-exposed tables,
    including the credential vault, verified in both directions (writes still work,
    anon reads are blocked). A silent bug that returned 403 on two real endpoints
    (Home's recent-entities feed, Payments' stored-card lookup) was found and fixed.
    Data export and account deletion exist in Account, not re-verified this session.

## Core outcome

The user can ask Adam, “What matters?” She knows their emails, calendar,
projects, goals, and ongoing tasks. The user can ask her to handle a request,
negotiate with someone, and create follow-up tasks while they carry on with life.

The deeper thesis is that computers should be delegated to, not operated by
people step by step. The device is the physical presence of that shift.
