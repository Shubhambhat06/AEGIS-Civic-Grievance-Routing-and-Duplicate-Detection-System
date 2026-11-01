// The portal's seal: an original mark (a shield over a ward street grid,
// ringed in saffron). It deliberately does not resemble the State Emblem
// of India or the insignia of any real government body.
export default function Seal({ size = 44 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 40 40" aria-hidden="true">
      <circle cx="20" cy="20" r="19" fill="none" stroke="#f28c28" strokeWidth="2" />
      <circle cx="20" cy="20" r="16" fill="none" stroke="#ffffff" strokeOpacity="0.35" strokeWidth="0.8" />
      <path d="M20 7.5 L29.5 11.3 V20 C29.5 26.2 25.5 30.6 20 32.5 C14.5 30.6 10.5 26.2 10.5 20 V11.3 Z" fill="#ffffff" />
      <path d="M13.5 18 H26.5 M13.5 23 H26.5 M17.2 12.8 V30 M22.8 12.8 V30" stroke="#0f2c5c" strokeWidth="1.5" />
      <circle cx="22.8" cy="18" r="2.2" fill="#f28c28" stroke="#0f2c5c" strokeWidth="1" />
    </svg>
  );
}
