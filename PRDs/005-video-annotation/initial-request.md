I want to create a new PRD-005. This will be a rather large one, so more phases than regular might be needed. I want to follow the pattern from PRD-004, so make sure to look into the structure from that one.

I want to extend the video-streamer and grab the stream in memory, and run it through a neural network using NX and/or axon to host a network. The annotated stream, I want to expose as a separate rtsp stream that can be picked up on QGC on a separate path (same port). The neural network I want to start with in YOLOv11. I also want to use the NCNN format.

This needs to be a flexible architecture allowing for a plugable network, for easy replacement as networks develop.

This architecture will in first version be a drone operator assistance tool, but will in near future be extended to run logic on drone for AI-driven navigation. The last part is out of scope for this PRD, but should be possible to extend later.

Initial research for Raspberry pi CM5 and networks can be found at @PRDs/005-video-annotation/initial-research.pdf  . Use this as starting point for inspiration, but run own investigation, if needed. 
