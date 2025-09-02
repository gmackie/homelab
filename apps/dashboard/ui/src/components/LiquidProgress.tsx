import { motion } from 'framer-motion'

interface LiquidProgressProps {
  value: number
  max?: number
  label?: string
  color?: string
  size?: number
}

export function LiquidProgress({ 
  value, 
  max = 100, 
  label = '', 
  color = '#00D9FF',
  size = 150 
}: LiquidProgressProps) {
  const percentage = (value / max) * 100
  const waveHeight = size * (1 - percentage / 100)

  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="absolute inset-0">
        <defs>
          <clipPath id={`liquid-clip-${label}`}>
            <circle cx={size/2} cy={size/2} r={size/2 - 5} />
          </clipPath>
          <linearGradient id={`liquid-gradient-${label}`} x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stopColor={color} stopOpacity={0.8} />
            <stop offset="100%" stopColor={color} stopOpacity={1} />
          </linearGradient>
        </defs>
        
        {/* Background circle */}
        <circle
          cx={size/2}
          cy={size/2}
          r={size/2 - 5}
          fill="transparent"
          stroke={`${color}33`}
          strokeWidth="2"
        />
        
        {/* Liquid fill with wave animation */}
        <motion.g clipPath={`url(#liquid-clip-${label})`}>
          <motion.rect
            x={0}
            y={waveHeight}
            width={size}
            height={size}
            fill={`url(#liquid-gradient-${label})`}
            initial={{ y: size }}
            animate={{ y: waveHeight }}
            transition={{ duration: 1, ease: "easeOut" }}
          />
          
          {/* Wave effect */}
          <motion.path
            d={`M0,${waveHeight} Q${size/4},${waveHeight-10} ${size/2},${waveHeight} T${size},${waveHeight} L${size},${size} L0,${size} Z`}
            fill={`url(#liquid-gradient-${label})`}
            animate={{
              d: [
                `M0,${waveHeight} Q${size/4},${waveHeight-10} ${size/2},${waveHeight} T${size},${waveHeight} L${size},${size} L0,${size} Z`,
                `M0,${waveHeight} Q${size/4},${waveHeight+10} ${size/2},${waveHeight} T${size},${waveHeight} L${size},${size} L0,${size} Z`,
                `M0,${waveHeight} Q${size/4},${waveHeight-10} ${size/2},${waveHeight} T${size},${waveHeight} L${size},${size} L0,${size} Z`
              ]
            }}
            transition={{
              duration: 3,
              repeat: Infinity,
              ease: "easeInOut"
            }}
          />
        </motion.g>
        
        {/* Outer ring */}
        <circle
          cx={size/2}
          cy={size/2}
          r={size/2 - 5}
          fill="transparent"
          stroke={color}
          strokeWidth="3"
          opacity={0.3}
        />
      </svg>
      
      {/* Center text */}
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <motion.div 
          className="text-3xl font-bold text-white"
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ delay: 0.5, type: "spring", stiffness: 200 }}
        >
          {percentage.toFixed(0)}%
        </motion.div>
        {label && (
          <div className="text-xs text-gray-300 mt-1">{label}</div>
        )}
      </div>
    </div>
  )
}