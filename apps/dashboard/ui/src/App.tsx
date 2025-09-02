import { useEffect, useState, useCallback, useMemo, useRef } from 'react'
import { motion, AnimatePresence, useAnimation } from 'framer-motion'
import { 
  Activity, HardDrive, Cpu, MemoryStick, Network, Container, Power, 
  RefreshCw, Zap, Globe, Shield, Gauge, Sparkles, Heart, Rocket,
  TrendingUp, TrendingDown, Server, Wifi, Database, Cloud
} from 'lucide-react'
import { 
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, 
  ResponsiveContainer, PieChart, Pie, Cell, BarChart, Bar
} from 'recharts'
import Particles from "react-particles"
import { loadSlim } from "tsparticles-slim"
import type { Engine } from "tsparticles-engine"
import Confetti from 'react-confetti'
import { useWindowSize, useIdle } from 'react-use'
import toast, { Toaster } from 'react-hot-toast'
import { GlowCard } from './components/GlowCard'
import { RippleButton } from './components/RippleButton'
import { LiquidProgress } from './components/LiquidProgress'
import { FloatingOrb } from './components/FloatingOrb'
import { Screensaver } from './components/Screensaver'
import { ArchitectureBadge } from './components/ArchitectureBadge'

interface SystemMetrics {
  timestamp: string
  cpu: {
    usage_percent: number[]
    core_count: number
    temperature: number
  }
  memory: {
    total: number
    used: number
    free: number
    used_percent: number
  }
  disk: Array<{
    path: string
    total: number
    used: number
    free: number
    used_percent: number
  }>
  network: {
    bytes_sent: number
    bytes_recv: number
    packets_sent: number
    packets_recv: number
  }
  docker: {
    container_count: number
    running_count: number
    containers: Array<{
      id: string
      name: string
      state: string
      status: string
      image: string
    }>
  }
  host: {
    hostname: string
    os: string
    platform: string
    uptime: number
    architecture: string
    is_multi_arch: boolean
    kubernetes?: {
      node_name: string
      node_labels: Record<string, string>
      is_arm: boolean
      is_amd64: boolean
      node_role: string
    }
    power: {
      estimated_watts: number
      power_efficiency: string
      architecture_type: string
    }
  }
}

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080'

// Beautiful color palette
const colors = {
  cpu: '#00D9FF',
  memory: '#FF00FF',
  disk: '#FFD700',
  network: '#00FF88',
  container: '#8B5CF6',
  success: '#10B981',
  danger: '#EF4444',
  warning: '#F59E0B'
}

function App() {
  const [metrics, setMetrics] = useState<SystemMetrics | null>(null)
  const [cpuHistory, setCpuHistory] = useState<any[]>([])
  const [memoryHistory, setMemoryHistory] = useState<any[]>([])
  const [selectedContainer, setSelectedContainer] = useState<string | null>(null)
  const [showConfetti, setShowConfetti] = useState(false)
  const [connectionStatus, setConnectionStatus] = useState<'connecting' | 'connected' | 'error'>('connecting')
  const [showScreensaver, setShowScreensaver] = useState(false)
  const controls = useAnimation()
  const { width, height } = useWindowSize()
  
  // Idle detection - show screensaver after 60 seconds of inactivity
  const isIdle = useIdle(60000) // 60 seconds
  
  useEffect(() => {
    if (isIdle && metrics && !showScreensaver) {
      setShowScreensaver(true)
      toast('Entering screensaver mode', {
        icon: '🌙',
        style: {
          borderRadius: '10px',
          background: '#333',
          color: '#fff',
        },
      })
    }
  }, [isIdle, metrics, showScreensaver])

  const particlesInit = useCallback(async (engine: Engine) => {
    await loadSlim(engine)
  }, [])

  const particlesOptions = useMemo(() => ({
    background: {
      color: { value: "transparent" },
    },
    fpsLimit: 120,
    particles: {
      color: {
        value: ["#00D9FF", "#FF00FF", "#FFD700", "#00FF88"],
      },
      move: {
        enable: true,
        speed: 0.5,
        direction: "none" as const,
        random: true,
        straight: false,
        outModes: { default: "bounce" as const },
      },
      number: {
        density: { enable: true, area: 1000 },
        value: 20,
      },
      opacity: {
        value: { min: 0.1, max: 0.3 },
        animation: {
          enable: true,
          speed: 1,
          minimumValue: 0.1,
          sync: false
        }
      },
      shape: { type: "circle" },
      size: {
        value: { min: 1, max: 3 },
        animation: {
          enable: true,
          speed: 2,
          minimumValue: 0.1,
          sync: false
        }
      },
    },
    detectRetina: true,
  }), [])

  useEffect(() => {
    const ws = new WebSocket(`${API_URL.replace('http', 'ws')}/ws`)
    
    ws.onopen = () => {
      setConnectionStatus('connected')
      toast.success('Connected to Dashboard!', {
        icon: '🚀',
        style: {
          borderRadius: '10px',
          background: '#333',
          color: '#fff',
        },
      })
    }
    
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data)
      setMetrics(data)
      
      const avgCpu = data.cpu.usage_percent.reduce((a: number, b: number) => a + b, 0) / data.cpu.usage_percent.length
      setCpuHistory(prev => [...prev.slice(-29), { time: new Date().toLocaleTimeString(), value: avgCpu }])
      setMemoryHistory(prev => [...prev.slice(-29), { time: new Date().toLocaleTimeString(), value: data.memory.used_percent }])
    }

    ws.onerror = () => {
      setConnectionStatus('error')
      toast.error('Connection lost!', {
        icon: '⚠️',
        style: {
          borderRadius: '10px',
          background: '#333',
          color: '#fff',
        },
      })
    }

    ws.onclose = () => {
      setConnectionStatus('error')
      setTimeout(() => window.location.reload(), 5000)
    }

    return () => ws.close()
  }, [])

  const handleContainerAction = async (containerId: string, action: string) => {
    try {
      const response = await fetch(`${API_URL}/container/action`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ container_id: containerId, action })
      })
      if (response.ok) {
        setShowConfetti(true)
        setTimeout(() => setShowConfetti(false), 3000)
        
        const actionEmoji = action === 'start' ? '▶️' : action === 'stop' ? '⏹️' : '🔄'
        toast.success(`Container ${action} successful!`, {
          icon: actionEmoji,
          style: {
            borderRadius: '10px',
            background: '#333',
            color: '#fff',
          },
        })
      }
    } catch (error) {
      toast.error('Action failed!', {
        style: {
          borderRadius: '10px',
          background: '#333',
          color: '#fff',
        },
      })
    }
  }

  const formatBytes = (bytes: number) => {
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
    if (bytes === 0) return '0 B'
    const i = Math.floor(Math.log(bytes) / Math.log(1024))
    return Math.round(bytes / Math.pow(1024, i) * 100) / 100 + ' ' + sizes[i]
  }

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    return `${days}d ${hours}h ${minutes}m`
  }

  if (!metrics) {
    return (
      <div className="flex items-center justify-center h-screen bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white relative overflow-hidden">
        <Particles id="tsparticles" init={particlesInit} options={particlesOptions} />
        
        {/* Floating orbs */}
        <FloatingOrb color="#00D9FF" size={200} delay={0} />
        <FloatingOrb color="#FF00FF" size={150} delay={2} />
        <FloatingOrb color="#FFD700" size={180} delay={4} />
        
        <motion.div className="text-center z-10">
          <motion.div
            animate={{ 
              rotate: 360,
              scale: [1, 1.1, 1]
            }}
            transition={{ 
              rotate: { duration: 2, repeat: Infinity, ease: "linear" },
              scale: { duration: 1, repeat: Infinity }
            }}
          >
            <Rocket className="w-20 h-20 mx-auto mb-6 text-transparent bg-gradient-to-r from-cyan-400 to-purple-400 bg-clip-text" 
                    style={{ stroke: 'url(#gradient)', strokeWidth: 1.5 }} />
          </motion.div>
          
          <motion.h1 
            className="text-4xl font-bold mb-4 bg-gradient-to-r from-cyan-400 via-purple-400 to-pink-400 bg-clip-text text-transparent"
            animate={{ 
              backgroundPosition: ['0%', '100%', '0%']
            }}
            transition={{ duration: 3, repeat: Infinity }}
            style={{ backgroundSize: '200% 100%' }}
          >
            Initializing Dashboard
          </motion.h1>
          
          <motion.div className="flex gap-2 justify-center">
            {[...Array(3)].map((_, i) => (
              <motion.div
                key={i}
                className="w-3 h-3 bg-gradient-to-r from-cyan-400 to-purple-400 rounded-full"
                animate={{ 
                  y: [0, -10, 0],
                  opacity: [0.3, 1, 0.3]
                }}
                transition={{ 
                  duration: 1,
                  repeat: Infinity,
                  delay: i * 0.2
                }}
              />
            ))}
          </motion.div>
        </motion.div>
      </div>
    )
  }

  const avgCpu = metrics.cpu.usage_percent.reduce((a, b) => a + b, 0) / metrics.cpu.usage_percent.length

  // Pie chart data for disk usage
  const diskChartData = metrics.disk.slice(0, 3).map(disk => ({
    name: disk.path.split('/').pop() || disk.path,
    value: disk.used,
    percent: disk.used_percent
  }))

  return (
    <>
      <AnimatePresence>
        {showScreensaver && metrics && (
          <Screensaver 
            metrics={metrics} 
            onExit={() => {
              setShowScreensaver(false)
              toast('Welcome back!', {
                icon: '👋',
                style: {
                  borderRadius: '10px',
                  background: '#333',
                  color: '#fff',
                },
              })
            }}
          />
        )}
      </AnimatePresence>
      
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900/50 to-slate-900 text-white p-4 overflow-hidden relative">
        <Toaster position="top-right" />
        {showConfetti && <Confetti width={width} height={height} recycle={false} numberOfPieces={200} />}
        
        <Particles id="tsparticles" init={particlesInit} options={particlesOptions} className="absolute inset-0" />
      
      {/* Floating background orbs */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <FloatingOrb color="#00D9FF" size={300} delay={0} duration={30} />
        <FloatingOrb color="#FF00FF" size={250} delay={5} duration={25} />
        <FloatingOrb color="#FFD700" size={200} delay={10} duration={35} />
      </div>
      
      <div className="relative z-10 max-w-7xl mx-auto">
        {/* Animated Header */}
        <motion.div 
          className="mb-8 text-center"
          initial={{ opacity: 0, y: -30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
        >
          <motion.div className="inline-flex items-center gap-4 mb-4">
            <motion.div
              animate={{ rotate: 360 }}
              transition={{ duration: 20, repeat: Infinity, ease: "linear" }}
            >
              <Sparkles className="w-8 h-8 text-yellow-400" />
            </motion.div>
            
            <h1 className="text-5xl font-bold bg-gradient-to-r from-cyan-400 via-purple-400 to-pink-400 bg-clip-text text-transparent">
              {metrics.host.hostname}
            </h1>
            
            <motion.div
              animate={{ rotate: -360 }}
              transition={{ duration: 20, repeat: Infinity, ease: "linear" }}
            >
              <Sparkles className="w-8 h-8 text-yellow-400" />
            </motion.div>
          </motion.div>
          
          <div className="flex items-center justify-center gap-6 text-sm mb-4">
            <motion.div 
              className="flex items-center gap-2"
              whileHover={{ scale: 1.05 }}
            >
              <Shield className="w-4 h-4 text-green-400" />
              <span className="text-gray-300">{metrics.host.os}</span>
            </motion.div>
            
            <motion.div 
              className="flex items-center gap-2"
              whileHover={{ scale: 1.05 }}
            >
              <Zap className="w-4 h-4 text-yellow-400" />
              <span className="text-gray-300">Uptime: {formatUptime(metrics.host.uptime)}</span>
            </motion.div>
            
            <motion.div 
              className="flex items-center gap-2"
              animate={{ opacity: [0.5, 1, 0.5] }}
              transition={{ duration: 2, repeat: Infinity }}
            >
              <Heart className="w-4 h-4 text-red-400" />
              <span className="text-gray-300">{new Date(metrics.timestamp).toLocaleTimeString()}</span>
            </motion.div>
          </div>
          
          {/* Architecture Info */}
          <div className="flex justify-center mb-6">
            <ArchitectureBadge 
              architecture={metrics.host.architecture}
              isMultiArch={metrics.host.is_multi_arch}
              kubernetes={metrics.host.kubernetes}
              power={metrics.host.power}
            />
          </div>
        </motion.div>

        {/* Main Grid */}
        <div className="grid grid-cols-12 gap-6">
          {/* CPU & Memory Liquid Progress */}
          <div className="col-span-6 lg:col-span-3">
            <GlowCard glowColor={colors.cpu} delay={0.1}>
              <div className="p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <Cpu className="w-5 h-5 text-cyan-400" />
                    <h3 className="font-semibold">CPU</h3>
                  </div>
                  <motion.div
                    animate={{ opacity: [0.5, 1, 0.5] }}
                    transition={{ duration: 2, repeat: Infinity }}
                  >
                    <TrendingUp className="w-4 h-4 text-cyan-400" />
                  </motion.div>
                </div>
                <div className="flex justify-center">
                  <LiquidProgress 
                    value={avgCpu} 
                    label="CPU" 
                    color={colors.cpu}
                    size={140}
                  />
                </div>
                <div className="text-center mt-4 text-sm text-gray-400">
                  {metrics.cpu.core_count} Cores Active
                </div>
              </div>
            </GlowCard>
          </div>

          <div className="col-span-6 lg:col-span-3">
            <GlowCard glowColor={colors.memory} delay={0.2}>
              <div className="p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <MemoryStick className="w-5 h-5 text-purple-400" />
                    <h3 className="font-semibold">Memory</h3>
                  </div>
                  <Database className="w-4 h-4 text-purple-400" />
                </div>
                <div className="flex justify-center">
                  <LiquidProgress 
                    value={metrics.memory.used_percent} 
                    label="RAM" 
                    color={colors.memory}
                    size={140}
                  />
                </div>
                <div className="text-center mt-4 text-sm text-gray-400">
                  {formatBytes(metrics.memory.used)} / {formatBytes(metrics.memory.total)}
                </div>
              </div>
            </GlowCard>
          </div>

          {/* Performance Chart */}
          <div className="col-span-12 lg:col-span-6">
            <GlowCard glowColor="rgba(99,102,241,0.5)" delay={0.3}>
              <div className="p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <Gauge className="w-5 h-5 text-indigo-400" />
                    <h3 className="font-semibold">System Performance</h3>
                  </div>
                  <motion.div
                    animate={{ rotate: 360 }}
                    transition={{ duration: 2, repeat: Infinity, ease: "linear" }}
                  >
                    <RefreshCw className="w-4 h-4 text-indigo-400" />
                  </motion.div>
                </div>
                <ResponsiveContainer width="100%" height={180}>
                  <AreaChart data={cpuHistory}>
                    <defs>
                      <linearGradient id="cpuGradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor={colors.cpu} stopOpacity={0.8}/>
                        <stop offset="95%" stopColor={colors.cpu} stopOpacity={0.1}/>
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="#374151" opacity={0.1} />
                    <XAxis dataKey="time" hide />
                    <YAxis domain={[0, 100]} hide />
                    <Tooltip 
                      contentStyle={{ 
                        backgroundColor: 'rgba(17, 24, 39, 0.9)', 
                        border: '1px solid rgba(99, 102, 241, 0.3)',
                        borderRadius: '12px',
                        backdropFilter: 'blur(10px)'
                      }} 
                    />
                    <Area 
                      type="monotone" 
                      dataKey="value" 
                      stroke={colors.cpu} 
                      fill="url(#cpuGradient)" 
                      strokeWidth={3}
                      animationDuration={1000}
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </GlowCard>
          </div>

          {/* Disk Usage with Pie Chart */}
          <div className="col-span-12 lg:col-span-4">
            <GlowCard glowColor={colors.disk} delay={0.4}>
              <div className="p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <HardDrive className="w-5 h-5 text-orange-400" />
                    <h3 className="font-semibold">Storage</h3>
                  </div>
                  <Cloud className="w-4 h-4 text-orange-400" />
                </div>
                
                <div className="flex items-center justify-center">
                  <ResponsiveContainer width={150} height={150}>
                    <PieChart>
                      <Pie
                        data={diskChartData}
                        cx="50%"
                        cy="50%"
                        innerRadius={40}
                        outerRadius={60}
                        paddingAngle={5}
                        dataKey="value"
                        animationBegin={0}
                        animationDuration={1000}
                      >
                        {diskChartData.map((_, index) => (
                          <Cell key={`cell-${index}`} fill={`hsl(${index * 120}, 70%, 50%)`} />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                
                <div className="space-y-2 mt-4">
                  {metrics.disk.slice(0, 3).map((disk, idx) => (
                    <motion.div 
                      key={idx}
                      className="flex items-center justify-between text-sm"
                      initial={{ opacity: 0, x: -20 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: 0.5 + idx * 0.1 }}
                    >
                      <span className="text-gray-400 flex items-center gap-2">
                        <div className={`w-2 h-2 rounded-full`} style={{ backgroundColor: `hsl(${idx * 120}, 70%, 50%)` }} />
                        {disk.path}
                      </span>
                      <span className={`font-bold ${disk.used_percent > 80 ? 'text-red-400' : 'text-green-400'}`}>
                        {disk.used_percent.toFixed(0)}%
                      </span>
                    </motion.div>
                  ))}
                </div>
              </div>
            </GlowCard>
          </div>

          {/* Network Activity */}
          <div className="col-span-12 lg:col-span-4">
            <GlowCard glowColor={colors.network} delay={0.5}>
              <div className="p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <Wifi className="w-5 h-5 text-green-400" />
                    <h3 className="font-semibold">Network</h3>
                  </div>
                  <motion.div
                    animate={{ opacity: [0.3, 1, 0.3] }}
                    transition={{ duration: 1.5, repeat: Infinity }}
                  >
                    <Globe className="w-4 h-4 text-green-400" />
                  </motion.div>
                </div>
                
                <div className="space-y-4">
                  <motion.div 
                    className="bg-gradient-to-r from-green-500/20 to-transparent p-3 rounded-xl"
                    whileHover={{ scale: 1.02 }}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <TrendingDown className="w-4 h-4 text-green-400" />
                        <span className="text-sm">Download</span>
                      </div>
                      <motion.span 
                        className="text-xl font-bold text-green-400"
                        animate={{ opacity: [0.7, 1, 0.7] }}
                        transition={{ duration: 2, repeat: Infinity }}
                      >
                        {formatBytes(metrics.network.bytes_recv)}
                      </motion.span>
                    </div>
                  </motion.div>
                  
                  <motion.div 
                    className="bg-gradient-to-r from-blue-500/20 to-transparent p-3 rounded-xl"
                    whileHover={{ scale: 1.02 }}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <TrendingUp className="w-4 h-4 text-blue-400" />
                        <span className="text-sm">Upload</span>
                      </div>
                      <motion.span 
                        className="text-xl font-bold text-blue-400"
                        animate={{ opacity: [0.7, 1, 0.7] }}
                        transition={{ duration: 2, repeat: Infinity, delay: 1 }}
                      >
                        {formatBytes(metrics.network.bytes_sent)}
                      </motion.span>
                    </div>
                  </motion.div>
                </div>
                
                <div className="mt-4 pt-4 border-t border-white/10">
                  <div className="grid grid-cols-2 gap-2 text-xs text-gray-400">
                    <div>
                      <div className="font-semibold text-gray-300">Packets In</div>
                      <div>{metrics.network.packets_recv.toLocaleString()}</div>
                    </div>
                    <div>
                      <div className="font-semibold text-gray-300">Packets Out</div>
                      <div>{metrics.network.packets_sent.toLocaleString()}</div>
                    </div>
                  </div>
                </div>
              </div>
            </GlowCard>
          </div>

          {/* Docker Containers */}
          <div className="col-span-12 lg:col-span-4">
            <GlowCard glowColor={colors.container} delay={0.6}>
              <div className="p-6">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <Server className="w-5 h-5 text-violet-400" />
                    <h3 className="font-semibold">Containers</h3>
                  </div>
                  <div className="flex items-center gap-2">
                    <motion.span 
                      className="text-lg font-bold text-green-400"
                      animate={{ scale: [1, 1.2, 1] }}
                      transition={{ duration: 2, repeat: Infinity }}
                    >
                      {metrics.docker.running_count}
                    </motion.span>
                    <span className="text-sm text-gray-400">/ {metrics.docker.container_count}</span>
                  </div>
                </div>
                
                <div className="space-y-2 max-h-64 overflow-y-auto">
                  <AnimatePresence>
                    {metrics.docker.containers.slice(0, 5).map((container, idx) => (
                      <motion.div 
                        key={container.id}
                        layout
                        initial={{ opacity: 0, scale: 0.8, x: -50 }}
                        animate={{ opacity: 1, scale: 1, x: 0 }}
                        exit={{ opacity: 0, scale: 0.8, x: 50 }}
                        transition={{ 
                          delay: idx * 0.05,
                          type: "spring",
                          stiffness: 200,
                          damping: 20
                        }}
                        className={`relative p-3 rounded-xl cursor-pointer transition-all ${
                          selectedContainer === container.id 
                            ? 'bg-gradient-to-r from-violet-600/30 to-purple-600/30 border border-violet-400/50' 
                            : 'bg-white/5 hover:bg-white/10 border border-white/10'
                        }`}
                        onClick={() => setSelectedContainer(selectedContainer === container.id ? null : container.id)}
                        whileHover={{ scale: 1.02, y: -2 }}
                        whileTap={{ scale: 0.98 }}
                      >
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-3">
                            <motion.div 
                              className={`w-2 h-2 rounded-full ${container.state === 'running' ? 'bg-green-400' : 'bg-red-400'}`}
                              animate={container.state === 'running' ? {
                                scale: [1, 1.5, 1],
                                opacity: [1, 0.5, 1]
                              } : {}}
                              transition={{ duration: 2, repeat: Infinity }}
                            />
                            <div>
                              <div className="text-sm font-semibold">{container.name.replace('/', '')}</div>
                              <div className="text-xs text-gray-400">{container.image.split(':')[0]}</div>
                            </div>
                          </div>
                          
                          <AnimatePresence>
                            {selectedContainer === container.id && (
                              <motion.div 
                                className="flex gap-2"
                                initial={{ opacity: 0, scale: 0 }}
                                animate={{ opacity: 1, scale: 1 }}
                                exit={{ opacity: 0, scale: 0 }}
                                transition={{ type: "spring", stiffness: 500, damping: 30 }}
                              >
                                {container.state === 'running' ? (
                                  <RippleButton
                                    onClick={(e) => {
                                      e?.stopPropagation()
                                      handleContainerAction(container.id, 'stop')
                                    }}
                                    variant="danger"
                                    className="!p-2"
                                  >
                                    <Power className="w-4 h-4" />
                                  </RippleButton>
                                ) : (
                                  <RippleButton
                                    onClick={(e) => {
                                      e?.stopPropagation()
                                      handleContainerAction(container.id, 'start')
                                    }}
                                    variant="success"
                                    className="!p-2"
                                  >
                                    <Power className="w-4 h-4" />
                                  </RippleButton>
                                )}
                                <RippleButton
                                  onClick={(e) => {
                                    e?.stopPropagation()
                                    handleContainerAction(container.id, 'restart')
                                  }}
                                  variant="primary"
                                  className="!p-2"
                                >
                                  <RefreshCw className="w-4 h-4" />
                                </RippleButton>
                              </motion.div>
                            )}
                          </AnimatePresence>
                        </div>
                      </motion.div>
                    ))}
                  </AnimatePresence>
                </div>
              </div>
            </GlowCard>
          </div>
        </div>
      </div>
    </div>
    </>
  )
}

export default App