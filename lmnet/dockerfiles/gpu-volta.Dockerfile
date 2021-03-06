FROM nvcr.io/nvidia/tensorflow:18.03-py3

MAINTAINER wakisaka@leapmind.io, masuda@leapmind.io

# TensorBoard
EXPOSE 6006

ENV LD_LIBRARY_PATH /usr/local/cuda/extras/CUPTI/lib64:${LD_LIBRARY_PATH}

RUN echo "deb http://ftp.jaist.ac.jp/ubuntu/ xenial main restricted universe multiverse \n\
deb-src http://ftp.jaist.ac.jp/ubuntu/ xenial main restricted universe multiverse \n\
deb http://ftp.jaist.ac.jp/ubuntu/ xenial-updates main restricted universe multiverse \n\
deb-src http://ftp.jaist.ac.jp/ubuntu/ xenial-updates main restricted universe multiverse \n\
deb http://ftp.jaist.ac.jp/ubuntu/ xenial-backports main restricted universe multiverse \n\
deb-src http://ftp.jaist.ac.jp/ubuntu/ xenial-backports main restricted universe multiverse \n\
deb http://security.ubuntu.com/ubuntu xenial-security main restricted universe multiverse \n\
deb-src http://security.ubuntu.com/ubuntu xenial-security main restricted universe multiverse" > /etc/apt/sources.list

RUN apt-get update && apt-get install -y \
    locales\
    python3 \
    python3-dev \
    python3-pip \
    python3-wheel \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Pillow and matplotlib has many dependencies for display.
RUN apt-get update && apt-get install -y \
    python3-pil \
    libjpeg8-dev \
    zlib1g-dev \
    python3-matplotlib \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Locale setting
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Reinstall NCCL
RUN echo "deb http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1604/x86_64 /" > /etc/apt/sources.list.d/nvidia-ml.list
ENV NCCL_VERSION=2.1.2-1+cuda9.0
RUN apt-get update && apt-get --reinstall install -y --no-install-recommends \
    libnccl2=$NCCL_VERSION \
    libnccl-dev=$NCCL_VERSION

# Create a wrapper for OpenMPI to allow running as root by default
RUN mv /usr/local/mpi/bin/mpirun /usr/local/mpi/bin/mpirun.real && \
    echo '#!/bin/bash' > /usr/local/mpi/bin/mpirun && \
    echo 'mpirun.real --allow-run-as-root "$@"' >> /usr/local/mpi/bin/mpirun && \
    chmod a+x /usr/local/mpi/bin/mpirun

RUN pip install -U pip setuptools

COPY requirements.txt /tmp/requirements.txt
COPY dev.requirements.txt /tmp/dev.requirements.txt
COPY test.requirements.txt /tmp/test.requirements.txt
COPY docs.requirements.txt /tmp/docs.requirements.txt
COPY dist.requirements.txt /tmp/dist.requirements.txt

WORKDIR /home/lmnet

# Install requirements
RUN pip install -r /tmp/requirements.txt

# Set env to install horovod with nccl and tensorflow option
ENV HOROVOD_GPU_ALLREDUCE NCCL
ENV HOROVOD_WITH_TENSORFLOW 1
# Set temporarily CUDA stubs to install Horovod
RUN ldconfig /usr/local/cuda-9.0/targets/x86_64-linux/lib/stubs
# Install requirements for distributed training
RUN pip install -r /tmp/dist.requirements.txt
# Unset temporarily CUDA stubs
RUN ldconfig

# Build coco. It needs numpy.
COPY third_party third_party
# https://github.com/cocodataset/cocoapi/blob/440d145a30b410a2a6032827c568cff5dc1d2abf/PythonAPI/setup.py#L2
RUN cd third_party/coco/PythonAPI && pip install -e .

# For development 
RUN apt-get update && apt-get install -y \
    x11-apps \
    imagemagick \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure OpenMPI to run good defaults:
#   --bind-to none --map-by slot --mca btl_tcp_if_exclude lo,docker0 --mca btl_vader_single_copy_mechanism none
RUN echo "hwloc_base_binding_policy = none" >> /usr/local/mpi/etc/openmpi-mca-params.conf && \
    echo "rmaps_base_mapping_policy = slot" >> /usr/local/mpi/etc/openmpi-mca-params.conf && \
    echo "btl_tcp_if_exclude = lo,docker0" >> /usr/local/mpi/etc/openmpi-mca-params.conf
