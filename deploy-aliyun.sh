set -e

if [ -d ./output ]; then
    rm -r ./output
fi

cd hugo
hugo -d ../output
cd ..

scp -r ./output root@182.92.236.155:~/hugo
