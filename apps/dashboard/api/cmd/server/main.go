package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/client"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

type SystemMetrics struct {
	Timestamp   time.Time       `json:"timestamp"`
	CPU         CPUMetrics      `json:"cpu"`
	Memory      MemoryMetrics   `json:"memory"`
	Disk        []DiskMetrics   `json:"disk"`
	Network     NetworkMetrics  `json:"network"`
	Docker      DockerMetrics   `json:"docker"`
	Host        HostInfo        `json:"host"`
}

type CPUMetrics struct {
	UsagePercent []float64 `json:"usage_percent"`
	CoreCount    int       `json:"core_count"`
	Temperature  float64   `json:"temperature"`
}

type MemoryMetrics struct {
	Total       uint64  `json:"total"`
	Used        uint64  `json:"used"`
	Free        uint64  `json:"free"`
	UsedPercent float64 `json:"used_percent"`
}

type DiskMetrics struct {
	Path        string  `json:"path"`
	Total       uint64  `json:"total"`
	Used        uint64  `json:"used"`
	Free        uint64  `json:"free"`
	UsedPercent float64 `json:"used_percent"`
}

type NetworkMetrics struct {
	BytesSent   uint64 `json:"bytes_sent"`
	BytesRecv   uint64 `json:"bytes_recv"`
	PacketsSent uint64 `json:"packets_sent"`
	PacketsRecv uint64 `json:"packets_recv"`
}

type DockerMetrics struct {
	ContainerCount int              `json:"container_count"`
	RunningCount   int              `json:"running_count"`
	Containers     []ContainerInfo  `json:"containers"`
}

type ContainerInfo struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	State   string `json:"state"`
	Status  string `json:"status"`
	Image   string `json:"image"`
}

type HostInfo struct {
	Hostname     string           `json:"hostname"`
	OS           string           `json:"os"`
	Platform     string           `json:"platform"`
	Uptime       uint64           `json:"uptime"`
	Architecture string           `json:"architecture"`
	IsMultiArch  bool             `json:"is_multi_arch"`
	Kubernetes   *KubernetesInfo  `json:"kubernetes,omitempty"`
	Power        PowerInfo        `json:"power"`
}

type KubernetesInfo struct {
	NodeName    string            `json:"node_name,omitempty"`
	NodeLabels  map[string]string `json:"node_labels,omitempty"`
	IsARM       bool              `json:"is_arm"`
	IsAMD64     bool              `json:"is_amd64"`
	NodeRole    string            `json:"node_role"`
}

type PowerInfo struct {
	EstimatedWatts   float64 `json:"estimated_watts"`
	PowerEfficiency  string  `json:"power_efficiency"`
	ArchitectureType string  `json:"architecture_type"`
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func getArchitecture() string {
	switch runtime.GOARCH {
	case "amd64":
		return "amd64"
	case "arm64":
		return "arm64"
	case "arm":
		return "arm"
	default:
		return runtime.GOARCH
	}
}

func getKubernetesInfo() *KubernetesInfo {
	// Try to get Kubernetes node information
	nodeName := os.Getenv("NODE_NAME")
	if nodeName == "" {
		// Try kubectl if available
		cmd := exec.Command("kubectl", "get", "node", "-o", "name")
		if output, err := cmd.Output(); err == nil {
			lines := strings.Split(strings.TrimSpace(string(output)), "\n")
			if len(lines) > 0 {
				nodeName = strings.TrimPrefix(lines[0], "node/")
			}
		}
	}
	
	if nodeName == "" {
		return nil
	}

	k8sInfo := &KubernetesInfo{
		NodeName: nodeName,
		NodeLabels: make(map[string]string),
	}

	// Get node labels
	cmd := exec.Command("kubectl", "get", "node", nodeName, "-o", "jsonpath={.metadata.labels}")
	if output, err := cmd.Output(); err == nil {
		// Parse labels (simplified parsing)
		labelsStr := strings.TrimSpace(string(output))
		if labelsStr != "" {
			// This is a simplified parsing - in production, use proper JSON parsing
			if strings.Contains(labelsStr, "arch") {
				arch := getArchitecture()
				k8sInfo.NodeLabels["arch"] = arch
				k8sInfo.IsARM = arch == "arm64" || arch == "arm"
				k8sInfo.IsAMD64 = arch == "amd64"
			}
			
			// Determine node role
			if strings.Contains(labelsStr, "master") || strings.Contains(labelsStr, "control-plane") {
				k8sInfo.NodeRole = "master"
			} else if strings.Contains(labelsStr, "edge") {
				k8sInfo.NodeRole = "edge"
			} else if strings.Contains(labelsStr, "storage") {
				k8sInfo.NodeRole = "storage"
			} else {
				k8sInfo.NodeRole = "worker"
			}
		}
	}

	return k8sInfo
}

func getPowerInfo() PowerInfo {
	arch := getArchitecture()
	var watts float64
	var efficiency string
	var archType string

	switch arch {
	case "amd64":
		watts = 45.0 // Typical NUC power consumption
		efficiency = "medium"
		archType = "Intel/AMD x86_64"
	case "arm64":
		watts = 7.0 // Raspberry Pi 4/5
		efficiency = "high"
		archType = "ARM Cortex-A"
	case "arm":
		watts = 2.5 // Pi Zero or older Pi
		efficiency = "ultra-high"
		archType = "ARM Cortex-A (32-bit)"
	default:
		watts = 25.0
		efficiency = "unknown"
		archType = "Unknown"
	}

	// Try to get more accurate power reading from system files
	if powerFile, err := os.ReadFile("/sys/class/power_supply/BAT0/power_now"); err == nil {
		if powerMicroWatts := strings.TrimSpace(string(powerFile)); powerMicroWatts != "" {
			// Convert from microwatts to watts (if available)
			// This is mainly for laptops/devices with battery info
		}
	}

	return PowerInfo{
		EstimatedWatts:   watts,
		PowerEfficiency:  efficiency,
		ArchitectureType: archType,
	}
}

func collectMetrics(dockerClient *client.Client) (*SystemMetrics, error) {
	metrics := &SystemMetrics{
		Timestamp: time.Now(),
	}

	cpuPercent, _ := cpu.Percent(time.Second, true)
	cpuCount, _ := cpu.Counts(true)
	metrics.CPU = CPUMetrics{
		UsagePercent: cpuPercent,
		CoreCount:    cpuCount,
	}

	vmem, _ := mem.VirtualMemory()
	metrics.Memory = MemoryMetrics{
		Total:       vmem.Total,
		Used:        vmem.Used,
		Free:        vmem.Free,
		UsedPercent: vmem.UsedPercent,
	}

	partitions, _ := disk.Partitions(false)
	for _, partition := range partitions {
		usage, err := disk.Usage(partition.Mountpoint)
		if err == nil {
			metrics.Disk = append(metrics.Disk, DiskMetrics{
				Path:        partition.Mountpoint,
				Total:       usage.Total,
				Used:        usage.Used,
				Free:        usage.Free,
				UsedPercent: usage.UsedPercent,
			})
		}
	}

	netIO, _ := net.IOCounters(false)
	if len(netIO) > 0 {
		metrics.Network = NetworkMetrics{
			BytesSent:   netIO[0].BytesSent,
			BytesRecv:   netIO[0].BytesRecv,
			PacketsSent: netIO[0].PacketsSent,
			PacketsRecv: netIO[0].PacketsRecv,
		}
	}

	if dockerClient != nil {
		containers, err := dockerClient.ContainerList(context.Background(), types.ContainerListOptions{All: true})
		if err == nil {
			metrics.Docker.ContainerCount = len(containers)
			for _, container := range containers {
				info := ContainerInfo{
					ID:     container.ID[:12],
					Name:   container.Names[0],
					State:  container.State,
					Status: container.Status,
					Image:  container.Image,
				}
				metrics.Docker.Containers = append(metrics.Docker.Containers, info)
				if container.State == "running" {
					metrics.Docker.RunningCount++
				}
			}
		}
	}

	hostInfo, _ := host.Info()
	arch := getArchitecture()
	k8sInfo := getKubernetesInfo()
	powerInfo := getPowerInfo()
	
	metrics.Host = HostInfo{
		Hostname:     hostInfo.Hostname,
		OS:           hostInfo.OS,
		Platform:     hostInfo.Platform,
		Uptime:       hostInfo.Uptime,
		Architecture: arch,
		IsMultiArch:  k8sInfo != nil && (k8sInfo.IsARM || k8sInfo.IsAMD64),
		Kubernetes:   k8sInfo,
		Power:        powerInfo,
	}

	return metrics, nil
}

func handleWebSocket(c *gin.Context, dockerClient *client.Client) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("WebSocket upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			metrics, err := collectMetrics(dockerClient)
			if err != nil {
				log.Printf("Error collecting metrics: %v", err)
				continue
			}

			if err := conn.WriteJSON(metrics); err != nil {
				log.Printf("WebSocket write error: %v", err)
				return
			}
		}
	}
}

func handleContainerAction(c *gin.Context, dockerClient *client.Client) {
	var req struct {
		ContainerID string `json:"container_id"`
		Action      string `json:"action"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()
	
	switch req.Action {
	case "start":
		err := dockerClient.ContainerStart(ctx, req.ContainerID, types.ContainerStartOptions{})
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	case "stop":
		timeout := 10
		err := dockerClient.ContainerStop(ctx, req.ContainerID, &timeout)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	case "restart":
		timeout := 10
		err := dockerClient.ContainerRestart(ctx, req.ContainerID, &timeout)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid action"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "success"})
}

func main() {
	dockerClient, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		log.Printf("Docker client initialization failed: %v", err)
	}

	r := gin.Default()

	r.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		
		c.Next()
	})

	r.GET("/metrics", func(c *gin.Context) {
		metrics, err := collectMetrics(dockerClient)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, metrics)
	})

	r.GET("/ws", func(c *gin.Context) {
		handleWebSocket(c, dockerClient)
	})

	r.POST("/container/action", func(c *gin.Context) {
		handleContainerAction(c, dockerClient)
	})

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "healthy"})
	})

	log.Println("Dashboard API starting on :8080")
	if err := r.Run(":8080"); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}