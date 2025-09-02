import { motion } from 'framer-motion'
import { Monitor, Cpu, Smartphone, Zap, Gauge } from 'lucide-react'

interface ArchitectureBadgeProps {
  architecture: string
  isMultiArch?: boolean
  kubernetes?: {
    node_role: string
    is_arm: boolean
    is_amd64: boolean
  }
  power: {
    estimated_watts: number
    power_efficiency: string
    architecture_type: string
  }
}

export function ArchitectureBadge({ 
  architecture, 
  isMultiArch, 
  kubernetes, 
  power 
}: ArchitectureBadgeProps) {
  
  const getArchIcon = () => {
    switch (architecture) {
      case 'amd64':
        return <Monitor className="w-5 h-5" />
      case 'arm64':
        return <Smartphone className="w-5 h-5" />
      case 'arm':
        return <Cpu className="w-5 h-5" />
      default:
        return <Cpu className="w-5 h-5" />
    }
  }

  const getArchColor = () => {
    switch (architecture) {
      case 'amd64':
        return {
          bg: 'from-blue-500/20 to-cyan-500/20',
          border: 'border-blue-500/40',
          text: 'text-blue-400',
          glow: 'shadow-[0_0_20px_rgba(59,130,246,0.3)]'
        }
      case 'arm64':
        return {
          bg: 'from-green-500/20 to-emerald-500/20',
          border: 'border-green-500/40',
          text: 'text-green-400',
          glow: 'shadow-[0_0_20px_rgba(34,197,94,0.3)]'
        }
      case 'arm':
        return {
          bg: 'from-purple-500/20 to-violet-500/20',
          border: 'border-purple-500/40',
          text: 'text-purple-400',
          glow: 'shadow-[0_0_20px_rgba(139,92,246,0.3)]'
        }
      default:
        return {
          bg: 'from-gray-500/20 to-gray-600/20',
          border: 'border-gray-500/40',
          text: 'text-gray-400',
          glow: 'shadow-[0_0_20px_rgba(107,114,128,0.3)]'
        }
    }
  }

  const getPowerEfficiencyColor = () => {
    switch (power.power_efficiency) {
      case 'ultra-high':
        return 'text-green-300'
      case 'high':
        return 'text-green-400'
      case 'medium':
        return 'text-yellow-400'
      default:
        return 'text-gray-400'
    }
  }

  const colors = getArchColor()

  return (
    <motion.div
      className={`bg-gradient-to-r ${colors.bg} backdrop-blur-sm rounded-xl p-4 border ${colors.border} ${colors.glow}`}
      whileHover={{ scale: 1.02, y: -2 }}
      transition={{ type: "spring", stiffness: 300, damping: 20 }}
    >
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-3">
          <motion.div
            className={colors.text}
            animate={{ 
              scale: [1, 1.1, 1],
              rotate: [0, 5, -5, 0]
            }}
            transition={{ 
              duration: 3, 
              repeat: Infinity,
              ease: "easeInOut"
            }}
          >
            {getArchIcon()}
          </motion.div>
          <div>
            <div className="font-bold text-white text-lg">
              {architecture.toUpperCase()}
            </div>
            <div className={`text-sm ${colors.text}`}>
              {power.architecture_type}
            </div>
          </div>
        </div>
        
        {isMultiArch && (
          <motion.div
            className="bg-gradient-to-r from-cyan-500/20 to-purple-500/20 px-2 py-1 rounded-lg border border-cyan-500/30"
            animate={{ opacity: [0.7, 1, 0.7] }}
            transition={{ duration: 2, repeat: Infinity }}
          >
            <span className="text-xs text-cyan-300 font-semibold">MULTI-ARCH</span>
          </motion.div>
        )}
      </div>

      {/* Kubernetes Info */}
      {kubernetes && (
        <div className="space-y-2 mb-3">
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${kubernetes.is_arm ? 'bg-green-400' : 'bg-blue-400'}`} />
            <span className="text-sm text-gray-300">
              Role: <span className={colors.text}>{kubernetes.node_role}</span>
            </span>
          </div>
        </div>
      )}

      {/* Power Information */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Zap className="w-4 h-4 text-yellow-400" />
            <span className="text-sm text-gray-300">Power</span>
          </div>
          <span className="text-sm font-bold text-yellow-400">
            {power.estimated_watts.toFixed(1)}W
          </span>
        </div>
        
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Gauge className="w-4 h-4 text-green-400" />
            <span className="text-sm text-gray-300">Efficiency</span>
          </div>
          <span className={`text-sm font-bold ${getPowerEfficiencyColor()}`}>
            {power.power_efficiency}
          </span>
        </div>
      </div>

      {/* Power efficiency bar */}
      <div className="mt-3">
        <div className="w-full bg-gray-700/50 rounded-full h-2 overflow-hidden">
          <motion.div
            className={`h-2 rounded-full bg-gradient-to-r ${
              power.power_efficiency === 'ultra-high' 
                ? 'from-green-400 to-emerald-300' 
                : power.power_efficiency === 'high'
                ? 'from-green-500 to-green-400'
                : 'from-yellow-500 to-yellow-400'
            }`}
            initial={{ width: 0 }}
            animate={{ 
              width: power.power_efficiency === 'ultra-high' ? '100%' 
                   : power.power_efficiency === 'high' ? '85%' 
                   : power.power_efficiency === 'medium' ? '60%' 
                   : '40%'
            }}
            transition={{ duration: 1.5, ease: "easeOut" }}
          />
        </div>
      </div>
    </motion.div>
  )
}