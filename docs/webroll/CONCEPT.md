# Webroll Overview

Webroll is a public trust and discovery network for the independent web.

It combines four things:

* a public registry of independent sites
* persistent owner identities
* public vouches between owners
* a share network that routes content based on source type

The goal is to make independent sites easier to discover, evaluate, and follow without reducing everything to platform algorithms.

## What Webroll is

Webroll is not a publishing platform and not a closed social network. Sites remain on their own domains, use their own feeds, and adopt no special protocol. Webroll adds a public identity, trust, and discovery layer on top.

A site can register with basic metadata: URL, optional feed URL, tags, site type, bio, registration date, owner identity, and liveness status.

An owner is the persistent unit of identity. One owner can control multiple sites. Owners can publicly vouch for other owners. Those vouches form a graph from which trust signals are derived.

## Core model

### Owners

Owners are persistent identities with a UUID and cryptographic key pair. They can operate under a pseudonym, may control multiple sites, and carry their trust history across domains.

### Sites

A site is a registered web property owned by an owner. Registration does not require installing software or changing how the site publishes.

### Vouches

A vouch is a unilateral public endorsement from one owner to another. It may include a reason. Vouches can be withdrawn, and recipients can disavow them. Vouches are public and permanent in history.

### Shares

A share is a user-posted URL routed through Webroll. Shares are append-only in v0.1 and are classified automatically by source:

* **Registered site share**: from a registered site; eligible for network discovery
* **External share**: from an unregistered independent site; visible in the sharer’s feed and may receive limited treatment until the site registers
* **Platform share**: from a platform source such as Reddit, YouTube, or X; visible in the sharer’s feed only and excluded from network discovery

This keeps sharing simple: users can share any URL, and the system decides how it should be routed.

## Trust and discovery

Webroll’s trust layer is based on public owner-to-owner vouches.

From the vouch graph, Webroll derives a continuous trust field called **density**. Density is not manually assigned and is never stored as canonical state. It is computed from the graph and updated as the graph changes.

In early versions, density is a network signal, not a moral verdict. It helps shape discovery, ranking, and default visibility, but it does not define truth or legitimacy.

Discovery is based on:

* source eligibility
* topic relevance and tags
* freshness
* derived trust signals from the vouch graph

Only shares from registered sites participate fully in network discovery. Platform content can still be read and shared, but it does not define the network.

## Two lanes

Webroll has two distinct lanes.

### Reader lane

Webroll works as a general feed reader. It can ingest RSS, Atom, RSSHub-generated feeds, newsletters, podcasts, forums, YouTube, Reddit, and other feed-like sources. Users can subscribe broadly and read anything.

### Network lane

When a user shares something, Webroll classifies the source and routes it according to source type. Registered-site shares can move into network discovery. Other content may remain visible only in personal or local surfaces.

This separation is central to the system: Webroll supports broad reading, but network discovery stays focused on the independent web.

## Classification, routing, and filtering

Webroll separates three concerns:

* **Classification**: what kind of source a URL comes from
* **Routing**: which surfaces that source is allowed to appear in
* **Filtering**: which source types a given user wants to see

Because source type is simple metadata, users can apply straightforward filters such as:

* hide Reddit
* hide X
* hide all platform content
* show only registered sites
* include unregistered independent sites

This makes the system flexible without making sharing complicated.

## Governance and moderation

Webroll enforces a network-wide safety floor, not a universal culture.

The safety floor excludes fraud, scams, illegal content, spam, content farms, harassment, targeted abuse, and malware. Everything above that floor is left to user judgment and emergent communities.

Moderation distinguishes between sites and identities:

* suspending a site does not automatically destroy the owner’s standing if other sites remain active
* owner-level consequences apply only when the identity itself is no longer in good standing

Anyone can flag content or behavior. Reviews are evidence-based, public, and tied to identifiable reviewers. Appeals use a different quorum than the original decision.

## Communities

Communities are not declared top-down. They emerge from the vouch graph and can be detected and exposed through the API. This allows group structure to arise from actual trust relationships rather than platform-assigned categories.

## Identity and auth

Each owner has a persistent cryptographic identity and a mutable domain handle.

If a domain changes or expires, the identity can continue by proving continuity with the key. This lets reputation survive domain changes.

Webroll can also provide authentication for third-party sites through Sign in with Webroll. That allows sites to request basic public identity context such as domain, tags, tenure, and trust-related signals without forcing users into platform accounts.

Public information includes site metadata, tags, bio, shares, vouch relationships, and derived trust state. Sensitive operational data such as email, IP, tokens, custody mode, and browsing behavior is not public.

## Data model

Webroll’s canonical state comes from append-only public event logs.

The three base logs are:

* `registry.jsonl` for registrations, updates, suspensions, and key events
* `vouches.jsonl` for vouches, withdrawals, disavowals, and flags
* `shares.jsonl` for shares

Application state is reconstructed from these logs. Active status, pending status, density, communities, and discovery surfaces are derived rather than stored as primary truth.

This makes the system auditable, portable, and replayable.

## API

Webroll exposes a public API.

Read endpoints cover sites, vouches, trust state, graph structure, clusters, shares, and feeds. Write endpoints cover registration, vouching, withdrawal, disavowal, flagging, and sharing. Full history remains available by cloning and replaying the public logs.

## Liveness

Webroll tracks whether registered sites remain reachable. Extended failure reduces routing weight and visibility but does not automatically erase the site. Recovery restores standing. Owners may voluntarily deregister, which immediately neutralizes their outbound trust effects.

## Launch logic

Webroll can deliver value on day one as a strong feed reader. The network layer then grows as more sites register, more owners vouch, and more registered-site shares enter discovery.

A founding cohort seeds the initial graph, governance process, and taxonomy. Over time, founder influence fades as the network becomes self-sustaining.

## What makes Webroll distinct

Webroll is built around a simple principle:

**Anyone can read broadly. Anyone can share any URL. But only the registered independent web participates fully in network discovery.**

That gives the system a clean shape:

* open input
* explicit source classification
* constrained routing
* public trust signals
* auditable state
* minimal central authority beyond the safety floor

In short, Webroll is a public trust, identity, and discovery layer for independent sites, built from append-only events and shaped by explicit human endorsement rather than opaque engagement algorithms.
