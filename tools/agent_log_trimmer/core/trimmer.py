from abc import ABC, abstractmethod
import re

class BaseTrimmer(ABC):
    """
    Base class for trimming logic for a specific build system.
    """
    
    @abstractmethod
    def is_noise(self, line: str) -> bool:
        """Returns True if the line should be completely removed."""
        pass

    @abstractmethod
    def is_error(self, line: str) -> bool:
        """Returns True if the line indicates an error (to anchor context)."""
        pass
