TEMPLATE = subdirs

# Include configuration to check for GC_WANT_PYTHON
include(src/gcconfig.pri)

# Define main application target, we call this
# different from src to avoid confusion with
# the src directory in the source tree
gc.file = src/src.pro

# Define dependencies to ensure link order
contains(DEFINES, GC_WANT_PYTHON) {
    # Define separate target for SIP bindings
    siplib.file = src/Python/SIP/sip_lib.pro
    
    # This ensures 'make sub-gc' triggers 'sub-siplib'
    gc.depends = siplib qwt
    
    # Ordered list of subdirectories to build
    # qwt -> siplib -> gc -> unittests
    unittests.depends = gc
    SUBDIRS = qwt siplib gc unittests
} else {
    gc.depends = qwt
    # Ordered list of subdirectories to build
    # qwt -> gc -> unittests
    unittests.depends = gc
    SUBDIRS = qwt gc unittests
}
