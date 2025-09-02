import { useEffect, useRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { 
  Activity, Cpu, MemoryStick, HardDrive, Network, 
  Zap, Heart, Server, Gauge
} from 'lucide-react'

interface ScreensaverProps {
  metrics: any
  onExit: () => void
}

export function Screensaver({ metrics, onExit }: ScreensaverProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const animationRef = useRef<number>()
  const particlesRef = useRef<any[]>([])
  
  const avgCpu = metrics.cpu.usage_percent.reduce((a: number, b: number) => a + b, 0) / metrics.cpu.usage_percent.length
  const memoryPercent = metrics.memory.used_percent
  const networkActivity = (metrics.network.bytes_sent + metrics.network.bytes_recv) / 1000000 // MB
  
  // Determine system state and colors based on load
  const getSystemState = () => {
    const load = (avgCpu + memoryPercent) / 2
    if (load < 30) return { state: 'idle', color: '#00FF88', speed: 0.5, particles: 30 }
    if (load < 50) return { state: 'normal', color: '#00D9FF', speed: 1, particles: 50 }
    if (load < 70) return { state: 'busy', color: '#FFD700', speed: 2, particles: 80 }
    return { state: 'intense', color: '#FF00FF', speed: 3, particles: 120 }
  }
  
  const systemState = getSystemState()
  
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    
    canvas.width = window.innerWidth
    canvas.height = window.innerHeight
    
    // Initialize particles based on system load
    class Particle {
      x: number
      y: number
      vx: number
      vy: number
      size: number
      color: string
      life: number
      maxLife: number
      
      constructor() {
        this.x = Math.random() * canvas.width
        this.y = Math.random() * canvas.height
        this.vx = (Math.random() - 0.5) * systemState.speed
        this.vy = (Math.random() - 0.5) * systemState.speed
        this.size = Math.random() * 3 + 1
        this.color = systemState.color
        this.maxLife = Math.random() * 100 + 100
        this.life = this.maxLife
      }
      
      update() {
        this.x += this.vx
        this.y += this.vy
        this.life--
        
        // Wrap around screen
        if (this.x < 0) this.x = canvas.width
        if (this.x > canvas.width) this.x = 0
        if (this.y < 0) this.y = canvas.height
        if (this.y > canvas.height) this.y = 0
        
        // Add some organic movement based on CPU load
        this.vx += (Math.random() - 0.5) * 0.1 * (avgCpu / 100)
        this.vy += (Math.random() - 0.5) * 0.1 * (avgCpu / 100)
        
        // Limit velocity
        const maxVel = systemState.speed * 2
        this.vx = Math.max(-maxVel, Math.min(maxVel, this.vx))
        this.vy = Math.max(-maxVel, Math.min(maxVel, this.vy))
      }
      
      draw(ctx: CanvasRenderingContext2D) {
        const opacity = this.life / this.maxLife
        ctx.save()
        ctx.globalAlpha = opacity * 0.6
        ctx.fillStyle = this.color
        ctx.shadowBlur = 10
        ctx.shadowColor = this.color
        ctx.beginPath()
        ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2)
        ctx.fill()
        ctx.restore()
      }
    }
    
    // Create initial particles
    particlesRef.current = Array.from({ length: systemState.particles }, () => new Particle())
    
    // Draw connections between nearby particles
    const drawConnections = () => {
      const connectionDistance = 150
      ctx.strokeStyle = systemState.color
      
      for (let i = 0; i < particlesRef.current.length; i++) {
        for (let j = i + 1; j < particlesRef.current.length; j++) {
          const dx = particlesRef.current[i].x - particlesRef.current[j].x
          const dy = particlesRef.current[i].y - particlesRef.current[j].y
          const distance = Math.sqrt(dx * dx + dy * dy)
          
          if (distance < connectionDistance) {
            ctx.save()
            ctx.globalAlpha = (1 - distance / connectionDistance) * 0.2
            ctx.beginPath()
            ctx.moveTo(particlesRef.current[i].x, particlesRef.current[i].y)
            ctx.lineTo(particlesRef.current[j].x, particlesRef.current[j].y)
            ctx.stroke()
            ctx.restore()
          }
        }
      }
    }
    
    // Animation loop
    const animate = () => {
      ctx.fillStyle = 'rgba(15, 23, 42, 0.1)'
      ctx.fillRect(0, 0, canvas.width, canvas.height)
      
      // Update and draw particles
      particlesRef.current = particlesRef.current.filter(p => p.life > 0)
      
      // Add new particles based on network activity
      if (particlesRef.current.length < systemState.particles) {
        const particlesToAdd = Math.min(
          Math.floor(networkActivity / 10) + 1,
          systemState.particles - particlesRef.current.length
        )
        for (let i = 0; i < particlesToAdd; i++) {
          particlesRef.current.push(new Particle())
        }
      }
      
      drawConnections()
      
      particlesRef.current.forEach(particle => {
        particle.update()
        particle.draw(ctx)
      })
      
      animationRef.current = requestAnimationFrame(animate)
    }
    
    animate()
    
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current)
      }
    }
  }, [avgCpu, memoryPercent, networkActivity, systemState])
  
  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    return `${days}d ${hours}h ${minutes}m`
  }
  
  return (
    <motion.div 
      className="fixed inset-0 bg-slate-900 z-50 cursor-pointer"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      onClick={onExit}
      onTouchStart={onExit}
    >
      <canvas ref={canvasRef} className="absolute inset-0" />
      
      {/* Floating metrics orbs */}
      <div className="absolute inset-0 pointer-events-none">
        {/* CPU Orb */}
        <motion.div
          className="absolute top-1/4 left-1/4"
          animate={{
            x: [0, 100, -50, 0],
            y: [0, -50, 100, 0],
            scale: [1, 1 + avgCpu / 100, 1]
          }}
          transition={{
            duration: 20,
            repeat: Infinity,
            ease: "easeInOut"
          }}
        >
          <div className="relative">
            <div
              className="w-32 h-32 rounded-full flex items-center justify-center"
              style={{
                background: `radial-gradient(circle, ${systemState.color}33, transparent)`,
                boxShadow: `0 0 ${50 + avgCpu}px ${systemState.color}44`
              }}
            >
              <div className="text-center">
                <Cpu className="w-8 h-8 mx-auto mb-2" style={{ color: systemState.color }} />
                <div className="text-2xl font-bold" style={{ color: systemState.color }}>
                  {avgCpu.toFixed(0)}%
                </div>
              </div>
            </div>
          </div>
        </motion.div>
        
        {/* Memory Orb */}
        <motion.div
          className="absolute top-1/3 right-1/3"
          animate={{
            x: [0, -80, 60, 0],
            y: [0, 100, -80, 0],
            scale: [1, 1 + memoryPercent / 100, 1]
          }}
          transition={{
            duration: 25,
            repeat: Infinity,
            ease: "easeInOut"
          }}
        >
          <div className="relative">
            <div
              className="w-32 h-32 rounded-full flex items-center justify-center"
              style={{
                background: `radial-gradient(circle, ${systemState.color}33, transparent)`,
                boxShadow: `0 0 ${50 + memoryPercent}px ${systemState.color}44`
              }}
            >
              <div className="text-center">
                <MemoryStick className="w-8 h-8 mx-auto mb-2" style={{ color: systemState.color }} />
                <div className="text-2xl font-bold" style={{ color: systemState.color }}>
                  {memoryPercent.toFixed(0)}%
                </div>
              </div>
            </div>
          </div>
        </motion.div>
        
        {/* Network Orb */}
        <motion.div
          className="absolute bottom-1/3 left-1/2"
          animate={{
            x: [0, 120, -100, 0],
            y: [0, -70, 50, 0],
            scale: [1, 1 + Math.min(networkActivity / 100, 1), 1]
          }}
          transition={{
            duration: 18,
            repeat: Infinity,
            ease: "easeInOut"
          }}
        >
          <div className="relative">
            <div
              className="w-32 h-32 rounded-full flex items-center justify-center"
              style={{
                background: `radial-gradient(circle, ${systemState.color}33, transparent)`,
                boxShadow: `0 0 ${50 + Math.min(networkActivity, 100)}px ${systemState.color}44`
              }}
            >
              <div className="text-center">
                <Network className="w-8 h-8 mx-auto mb-2" style={{ color: systemState.color }} />
                <div className="text-lg font-bold" style={{ color: systemState.color }}>
                  {networkActivity.toFixed(1)} MB/s
                </div>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
      
      {/* Center display */}
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
        <motion.div
          className="text-center"
          animate={{
            scale: [0.95, 1.05, 0.95],
            opacity: [0.7, 1, 0.7]
          }}
          transition={{
            duration: 4,
            repeat: Infinity,
            ease: "easeInOut"
          }}
        >
          <motion.div
            animate={{ rotate: 360 }}
            transition={{ duration: 30, repeat: Infinity, ease: "linear" }}
          >
            <Heart 
              className="w-16 h-16 mx-auto mb-4" 
              style={{ 
                color: systemState.color,
                filter: `drop-shadow(0 0 30px ${systemState.color})`
              }} 
            />
          </motion.div>
          
          <h1 className="text-6xl font-bold mb-2" style={{ color: systemState.color }}>
            {metrics.host.hostname}
          </h1>
          
          <div className="text-2xl mb-4" style={{ color: `${systemState.color}CC` }}>
            System {systemState.state}
          </div>
          
          <div className="flex items-center justify-center gap-8 text-lg" style={{ color: `${systemState.color}99` }}>
            <div className="flex items-center gap-2">
              <Zap className="w-5 h-5" />
              <span>Uptime: {formatUptime(metrics.host.uptime)}</span>
            </div>
            <div className="flex items-center gap-2">
              <Server className="w-5 h-5" />
              <span>{metrics.docker.running_count}/{metrics.docker.container_count} containers</span>
            </div>
          </div>
          
          <motion.div
            className="mt-8 text-sm opacity-50"
            animate={{ opacity: [0.3, 0.6, 0.3] }}
            transition={{ duration: 2, repeat: Infinity }}
          >
            Touch anywhere to return
          </motion.div>
        </motion.div>
      </div>
      
      {/* Pulsing rings based on system load */}
      <svg className="absolute inset-0 pointer-events-none" width="100%" height="100%">
        <motion.circle
          cx="50%"
          cy="50%"
          r="200"
          fill="none"
          stroke={systemState.color}
          strokeWidth="1"
          opacity="0.2"
          animate={{
            r: [200, 300, 200],
            opacity: [0.2, 0, 0.2]
          }}
          transition={{
            duration: 4 / systemState.speed,
            repeat: Infinity,
            ease: "easeOut"
          }}
        />
        <motion.circle
          cx="50%"
          cy="50%"
          r="250"
          fill="none"
          stroke={systemState.color}
          strokeWidth="1"
          opacity="0.15"
          animate={{
            r: [250, 350, 250],
            opacity: [0.15, 0, 0.15]
          }}
          transition={{
            duration: 4 / systemState.speed,
            repeat: Infinity,
            ease: "easeOut",
            delay: 1
          }}
        />
        <motion.circle
          cx="50%"
          cy="50%"
          r="300"
          fill="none"
          stroke={systemState.color}
          strokeWidth="1"
          opacity="0.1"
          animate={{
            r: [300, 400, 300],
            opacity: [0.1, 0, 0.1]
          }}
          transition={{
            duration: 4 / systemState.speed,
            repeat: Infinity,
            ease: "easeOut",
            delay: 2
          }}
        />
      </svg>
    </motion.div>
  )
}