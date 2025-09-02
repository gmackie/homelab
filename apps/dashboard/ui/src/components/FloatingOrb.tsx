import { motion } from 'framer-motion'

interface FloatingOrbProps {
  color: string
  size?: number
  delay?: number
  duration?: number
}

export function FloatingOrb({ color, size = 100, delay = 0, duration = 20 }: FloatingOrbProps) {
  return (
    <motion.div
      className="absolute pointer-events-none"
      initial={{ x: 0, y: 0 }}
      animate={{
        x: [0, 100, -50, 0],
        y: [0, -100, 50, 0],
      }}
      transition={{
        duration,
        repeat: Infinity,
        delay,
        ease: "easeInOut"
      }}
    >
      <motion.div
        className="relative"
        animate={{
          scale: [1, 1.2, 1],
          rotate: [0, 180, 360]
        }}
        transition={{
          duration: duration / 2,
          repeat: Infinity,
          ease: "easeInOut"
        }}
      >
        <div
          className="rounded-full blur-3xl opacity-30"
          style={{
            width: size,
            height: size,
            background: `radial-gradient(circle, ${color}, transparent)`,
            boxShadow: `0 0 ${size}px ${color}`
          }}
        />
      </motion.div>
    </motion.div>
  )
}