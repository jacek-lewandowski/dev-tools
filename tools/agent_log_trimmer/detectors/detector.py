from typing import List, Optional
from agent_log_trimmer.core.demuxer import BaseDemuxer
from agent_log_trimmer.core.trimmer import BaseTrimmer

def detect_demuxer(lines: List[str]) -> Optional[BaseDemuxer]:
    """Detects which multiplexer was used (Earthly, Bazel, Docker, etc)."""
    # Look at the first 100 lines for signatures
    sample = lines[:100]
    
    # Simple Earthly detection: lots of `-->` or `*failed* |` or target formats
    for line in sample:
        if line.startswith("ERROR ") and "/Earthfile:" in line:
            from agent_log_trimmer.systems.earthly import EarthlyDemuxer
            return EarthlyDemuxer()
        if "| --> " in line or "| [INFO]" in line:
            from agent_log_trimmer.systems.earthly import EarthlyDemuxer
            return EarthlyDemuxer()
            
    # Simple Bazel detection
    for line in sample:
        if line.startswith("INFO: Analyzed target ") or line.startswith("INFO: Found "):
            from agent_log_trimmer.systems.bazel import BazelDemuxer
            return BazelDemuxer()
            
    # Simple Docker Buildx detection
    for line in sample:
        if line.startswith("#") and " [" in line and "/ " in line:
            from agent_log_trimmer.systems.docker import DockerDemuxer
            return DockerDemuxer()

    return None

def detect_trimmers(lines: List[str]) -> List[BaseTrimmer]:
    """Detects inner build tools (Maven, NPM, Spring, etc) from a target's stream."""
    sample = lines[:200]
    sample_str = "\\n".join(sample)
    trimmers = []
    
    if "mvn " in sample_str or "[INFO] Scanning for projects..." in sample_str or "BUILD FAILURE" in sample_str:
        from agent_log_trimmer.systems.maven import MavenTrimmer
        trimmers.append(MavenTrimmer())
        
    if "npm " in sample_str or "npm WARN" in sample_str or "npm ERR!" in sample_str:
        from agent_log_trimmer.systems.npm import NpmTrimmer
        trimmers.append(NpmTrimmer())
        
    if "pip install" in sample_str or "Requirement already satisfied:" in sample_str:
        from agent_log_trimmer.systems.pip import PipTrimmer
        trimmers.append(PipTrimmer())
        
    if ":: Spring Boot ::" in sample_str or "MockHttpServletRequest:" in sample_str:
        from agent_log_trimmer.systems.spring import SpringTrimmer
        trimmers.append(SpringTrimmer())
        
    if "gradlew" in sample_str or "> Task :" in sample_str:
        from agent_log_trimmer.systems.gradle import GradleTrimmer
        trimmers.append(GradleTrimmer())
        
    return trimmers
