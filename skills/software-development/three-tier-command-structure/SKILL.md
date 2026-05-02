---
name: three-tier-command-structure
category: software-development
description: A structured orchestration process for complex coding, research, and system design tasks, ensuring alignment, quality control, and non-blocking execution with strict integrity constraints.
---

# Three-Tier Command Structure (with Integrity Protocol)

This skill defines the organizational blueprint for handling complex technical tasks. It prevents \"implementation drift\" and \"execution deception\" by separating goal definition (Butler), technical orchestration (Lead Engineer), and execution (Workers).

## 🏛️ The Hierarchy

### 1. Butler (Top Tier) - Goal Definition & Delivery
**Role**: The interface between the user and the technical execution.
- **Primary Objective**: Ensure the target is crystal clear and the delivery is noise-free.
- **Key Actions**:
    - **Alignment (The Grill)**: Actively \"grills\" the user to eliminate ambiguity, define edge cases, and set success criteria.
    - **Resource Dispatch**: Determines which technical path to take and assigns the Lead Engineer.
    - **Strict Audit**: Audits the final output against the initial \"grilled\" requirements AND the **Evidence Chain** before delivery.

### 2. Lead Engineer (Middle Tier) - Orchestration & QC
**Role**: The technical architect and quality gatekeeper.
- **Primary Objective**: Decompose high-level goals into a verifiable execution plan.
- **Key Actions**:
    - **Decomposition**: Breaks the goal into atomic, executable tasks.
    - **Active Monitoring**: Implementing a **Polling Mechanism** (checking logs/files) to track Worker progress.
    - **Integration**: Collects outputs from Workers and synthesizes them into a coherent result.
    - **Evidence Chain Production**: MUST produce a timestamped log of all execution steps (session IDs, start/end times) to prove the process was followed.

### 3. Workers (Bottom Tier) - Implementation
**Role**: The tactical executors.
- **Primary Objective**: Execute atomic tasks with high precision.
- **Key Actions**: Perform actual coding, searching, reading, or fixing as directed by the Lead Engineer.

---

## 🔄 Operational Workflow (Async-First)

### Phase 1: Alignment (Synchronous/Delegated)
- **Action**: `delegate_task` to a Butler subagent.
- **Process**: The Butler performs the \"Grill\" session.
- **Exit Condition**: User confirms the target and delivery format.

### Phase 2: Execution (Background/Asynchronous)
- **Action**: `terminal(background=True, notify_on_complete=True)` to launch a **Monitoring Main Process** (the backgroundized Lead Eng).
- **Internal Loop**:
    1. Lead Eng dispatches atomic Worker tasks via `terminal(background=True, notify_on_complete=False)`.
    2. Lead Eng performs **Active Polling** of output files or `process(action='poll')`.
    3. Lead Eng assembles the **Evidence Chain** (Execution Logs).
- **Constraint**: No complex Python logic should be wrapped in a single background call without prior transparent disclosure.

### Phase 3: Delivery (Synchronous)
- **Trigger**: System sends `[IMPORTANT: Background process ... completed]` notification.
- **Action**: Butler reads the final report, **verifies the Evidence Chain**, and presents the result.

---

## ⚠️ Integrity Protocol (Non-Negotiable)

### 1. Anti-Deception Guardrails
- **No Phantom Starts**: NEVER state a task is \"running in background\" without a corresponding `tool_call` to `terminal` or `cronjob`.
- **Tool Proof**: If the user questions the state, provide the exact `session_id` and timestamp of the call.
- **No Script Mimicry**: Do not replace an Agent-driven workflow with a single monolithic Python script to fake the process.

### 2. Verification Standards
- A task is only \"Completed\" if it provides an **Evidence Chain** (e.g., `T+0s: Action A`).
- If the Evidence Chain is missing or fragmented, the result is rejected and the process must be restarted.

### 3. Monitoring Truths
- **Trust the Notification**: Rely on `notify_on_complete=True`.
- **Skepticism of Process List**: Do not rely on `process(action='list')` as the sole proof of life. Maintain an internal registry of expected completion times.
