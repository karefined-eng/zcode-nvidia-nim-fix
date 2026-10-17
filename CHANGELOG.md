# Changelog

All notable changes to `zcode-nvidia-nim-fix` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Gemini model support (reasoning profiles, model limits, sanitization)
- Enhanced provider detection (NVIDIA, Gemini, other providers)
- Refactored sanitization logic for multiple provider types

### Changed
- Refactored `sanitize_chat_completion_body()` to handle 3 provider types
- Updated `model_limits.py` with Gemini model limits
- Updated `model_profiles.py` with Gemini reasoning profiles
- Added `is_google_gemini_provider()` function

### Fixed
- Provider detection now correctly identifies Gemini by base URL or provider name
- Gemini `extra_body` is now stripped automatically
- Gemini `reasoning_effort` is preserved if valid (low/medium/high)

## [0.3.0] - 2026-10-13

### Added
- Gemini model support across three files:
  - `nvidia_nim_proxy/model_profiles.py` - 5 Gemini reasoning profiles
  - `nvidia_nim_proxy/model_limits.py` - Gemini model limits (1M context, 16K output)
  - `nvidia_nim_proxy/sanitizer.py` - Gemini-specific sanitization logic
- Repository SEO enhancement plan
- Enhanced README with badge infrastructure

### Changed
- Refactored `sanitize_chat_completion_body()` handler for 3 provider types
- Provider detection now distinguishes NVIDIA vs Gemini vs other providers
- All 318 existing tests pass with Gemini additions

### Fixed
- Provider detection correctly identifies Gemini (not misidentified as NVIDIA)
- `extra_body` stripping works for NVIDIA (original ZCode bug fix)
- `reasoning_effort` preservation for Gemini models

## [0.2.1] - 2026-10-10

### Added
- Repository worktree cleanup (removed obsolete `kiwi-icebreaker` and `fate-machine` worktrees)
- Agent Manager session management

### Fixed
- Removed obsolete git worktrees that were no longer active

## [0.2.0] - 2026-10-10

### Added
- Initial repository structure
- NVIDIA NIM proxy with ZCode `extra_body` fixing
- Model catalog, key pooling, dashboard, auto-start/watchdog
- Comprehensive documentation (docs/AGENTS.md, docs/origin.md)

### Fixed
- Initial setup and configuration

---

*This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).*