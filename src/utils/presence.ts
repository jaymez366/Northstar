export function formatLastSeen (lastSeenAt: string | null | undefined, now = Date.now()) {
  if (!lastSeenAt) return 'Last seen unavailable'

  const timestamp = Date.parse(lastSeenAt)
  if (!Number.isFinite(timestamp)) return 'Last seen unavailable'

  const elapsedSeconds = Math.max(0, Math.floor((now - timestamp) / 1000))
  if (elapsedSeconds < 60) return 'Last seen just now'

  if (elapsedSeconds < 7 * 24 * 60 * 60) {
    const [unit, divisor]: [Intl.RelativeTimeFormatUnit, number] = elapsedSeconds < 60 * 60
      ? ['minute', 60]
      : elapsedSeconds < 24 * 60 * 60
        ? ['hour', 60 * 60]
        : ['day', 24 * 60 * 60]
    const elapsed = Math.floor(elapsedSeconds / divisor)
    return `Last seen ${new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' }).format(-elapsed, unit)}`
  }

  return `Last seen ${new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(timestamp)}`
}

export function formatPresenceLabel (
  online: boolean | null | undefined,
  lastSeenAt: string | null | undefined,
  now = Date.now(),
) {
  if (online === true) return 'Online'
  if (online !== false) return 'Status unavailable'
  return `Offline · ${formatLastSeen(lastSeenAt, now)}`
}
