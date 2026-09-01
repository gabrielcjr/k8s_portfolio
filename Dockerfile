FROM arm64v8/node

WORKDIR /home/app

COPY . .

RUN npm i

CMD ["node", "index.js"]

EXPOSE 3000